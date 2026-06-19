package service

import (
	"encoding/json"
	"fmt"
	"net"
	"net/netip"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/alireza0/s-ui/database"
	"github.com/alireza0/s-ui/database/model"
	"github.com/alireza0/s-ui/util/common"

	"golang.zx2c4.com/wireguard/wgctrl/wgtypes"
	"gorm.io/gorm"
)

const wireGuardSchemaVersion = 2

type WireGuardExport struct {
	Name     string `json:"name"`
	Filename string `json:"filename"`
	Config   string `json:"config"`
}

func mapValue(value interface{}) map[string]interface{} {
	result, _ := value.(map[string]interface{})
	return result
}

func listValue(value interface{}) []interface{} {
	result, _ := value.([]interface{})
	return result
}

func stringValue(value interface{}) string {
	result, _ := value.(string)
	return strings.TrimSpace(result)
}

func boolValue(value interface{}, fallback bool) bool {
	result, ok := value.(bool)
	if !ok {
		return fallback
	}
	return result
}

func intValue(value interface{}) int {
	switch typed := value.(type) {
	case float64:
		return int(typed)
	case int:
		return typed
	case json.Number:
		result, _ := typed.Int64()
		return int(result)
	case string:
		result, _ := strconv.Atoi(typed)
		return result
	default:
		return 0
	}
}

func stringsValue(value interface{}) []string {
	values := listValue(value)
	result := make([]string, 0, len(values))
	for _, item := range values {
		if text := stringValue(item); text != "" {
			result = append(result, text)
		}
	}
	if len(result) == 0 {
		if text := stringValue(value); text != "" {
			for _, item := range strings.Split(text, ",") {
				if item = strings.TrimSpace(item); item != "" {
					result = append(result, item)
				}
			}
		}
	}
	return result
}

func interfaceStrings(values []string) []interface{} {
	result := make([]interface{}, 0, len(values))
	for _, value := range values {
		result = append(result, value)
	}
	return result
}

func parsePrefix(value, field string) (netip.Prefix, error) {
	prefix, err := netip.ParsePrefix(strings.TrimSpace(value))
	if err != nil {
		return netip.Prefix{}, common.NewErrorf("%s is not a valid CIDR: %s", field, value)
	}
	return prefix, nil
}

func validateTunnel(value string, ipv6 bool) (netip.Prefix, error) {
	prefix, err := parsePrefix(value, "WireGuard network prefix")
	if err != nil {
		return netip.Prefix{}, err
	}
	if prefix.Addr().Is6() != ipv6 || prefix != prefix.Masked() {
		return netip.Prefix{}, common.NewErrorf("WireGuard network prefix must be a canonical IPv%d network", map[bool]int{false: 4, true: 6}[ipv6])
	}
	if ipv6 {
		if prefix.Bits() < 48 || prefix.Bits() > 124 {
			return netip.Prefix{}, common.NewError("IPv6 WireGuard network prefix must be between /48 and /124")
		}
		if prefix.Addr().IsLinkLocalUnicast() {
			return netip.Prefix{}, common.NewError("link-local IPv6 ranges must not be used as the WireGuard virtual network")
		}
	} else if prefix.Bits() < 8 || prefix.Bits() > 30 {
		return netip.Prefix{}, common.NewError("IPv4 WireGuard network prefix must be between /8 and /30")
	}
	return prefix, nil
}

func normalizeAndValidateWireGuard(data json.RawMessage) (json.RawMessage, error) {
	var root map[string]interface{}
	if err := json.Unmarshal(data, &root); err != nil {
		return nil, err
	}
	if stringValue(root["type"]) != "wireguard" {
		return data, nil
	}
	strict := intValue(root["wireguard_schema"]) >= wireGuardSchemaVersion
	if !strict {
		return data, nil
	}
	root["wireguard_schema"] = wireGuardSchemaVersion
	if stringValue(root["tag"]) == "" {
		return nil, common.NewError("WireGuard tag is required")
	}
	if key := stringValue(root["private_key"]); key == "" {
		return nil, common.NewError("WireGuard server private key is required")
	} else if _, err := wgtypes.ParseKey(key); err != nil {
		return nil, common.NewErrorf("invalid WireGuard server private key: %v", err)
	}

	var tunnel4, tunnel6 netip.Prefix
	var err error
	if value := stringValue(root["tunnel_ipv4_cidr"]); value != "" {
		tunnel4, err = validateTunnel(value, false)
		if err != nil {
			return nil, err
		}
	}
	if value := stringValue(root["tunnel_ipv6_cidr"]); value != "" {
		tunnel6, err = validateTunnel(value, true)
		if err != nil {
			return nil, err
		}
	}
	if !tunnel4.IsValid() && !tunnel6.IsValid() {
		return nil, common.NewError("at least one WireGuard virtual network prefix is required")
	}

	addresses := stringsValue(root["address"])
	if len(addresses) == 0 {
		return nil, common.NewError("at least one WireGuard endpoint address is required")
	}
	endpointAddresses := make(map[netip.Addr]struct{}, len(addresses))
	for _, value := range addresses {
		prefix, prefixErr := parsePrefix(value, "WireGuard endpoint address")
		if prefixErr != nil {
			return nil, prefixErr
		}
		if prefix.Bits() != prefix.Addr().BitLen() {
			return nil, common.NewErrorf("WireGuard endpoint address %s must use /32 for IPv4 or /128 for IPv6", value)
		}
		if prefix.Addr().Is4() && (!tunnel4.IsValid() || !tunnel4.Contains(prefix.Addr())) {
			return nil, common.NewErrorf("WireGuard endpoint address %s is outside the IPv4 virtual network", value)
		}
		if prefix.Addr().Is6() && (!tunnel6.IsValid() || !tunnel6.Contains(prefix.Addr())) {
			return nil, common.NewErrorf("WireGuard endpoint address %s is outside the IPv6 virtual network", value)
		}
		if _, exists := endpointAddresses[prefix.Addr()]; exists {
			return nil, common.NewErrorf("WireGuard endpoint address %s is duplicated", value)
		}
		endpointAddresses[prefix.Addr()] = struct{}{}
	}
	if stringValue(root["advertised_endpoint_host"]) == "" {
		return nil, common.NewError("client endpoint host is required and must identify the WireGuard UDP entrypoint")
	}
	if intValue(root["advertised_endpoint_port"]) < 1 || intValue(root["advertised_endpoint_port"]) > 65535 {
		return nil, common.NewError("client endpoint port must be between 1 and 65535")
	}

	peers := listValue(root["peers"])
	seenPrefixes := make([]netip.Prefix, 0, len(peers)*2)
	for index, rawPeer := range peers {
		peer := mapValue(rawPeer)
		if peer == nil {
			return nil, common.NewErrorf("WireGuard peer %d must be an object", index+1)
		}
		mode := stringValue(peer["peer_mode"])
		if mode == "" {
			mode = "roaming_client"
			peer["peer_mode"] = mode
		}
		if mode != "roaming_client" && mode != "static_peer" && mode != "site_to_site" {
			return nil, common.NewErrorf("WireGuard peer %d has an unsupported mode", index+1)
		}
		if mode == "roaming_client" {
			delete(peer, "address")
			delete(peer, "port")
			delete(peer, "static_remote_address")
			delete(peer, "static_remote_port")
		} else if stringValue(peer["static_remote_address"]) == "" || intValue(peer["static_remote_port"]) < 1 {
			return nil, common.NewErrorf("WireGuard peer %d requires a static remote address and port", index+1)
		}
		if key := stringValue(peer["public_key"]); key == "" {
			return nil, common.NewErrorf("WireGuard peer %d public key is required", index+1)
		} else if _, keyErr := wgtypes.ParseKey(key); keyErr != nil {
			return nil, common.NewErrorf("WireGuard peer %d has an invalid public key", index+1)
		}
		if key := stringValue(peer["pre_shared_key"]); key != "" {
			if _, keyErr := wgtypes.ParseKey(key); keyErr != nil {
				return nil, common.NewErrorf("WireGuard peer %d has an invalid pre-shared key", index+1)
			}
		}

		serverAllowed := stringsValue(peer["server_allowed_ips"])
		if len(serverAllowed) == 0 {
			for _, candidate := range []string{stringValue(peer["assigned_ipv4"]), stringValue(peer["assigned_ipv6"])} {
				if candidate != "" {
					serverAllowed = append(serverAllowed, candidate)
				}
			}
		}
		if len(serverAllowed) == 0 {
			serverAllowed = stringsValue(peer["allowed_ips"])
		}
		if len(serverAllowed) == 0 {
			return nil, common.NewErrorf("WireGuard peer %d requires an assigned /32 or /128 address", index+1)
		}
		seenFamily := map[bool]bool{}
		for _, value := range serverAllowed {
			prefix, prefixErr := parsePrefix(value, fmt.Sprintf("WireGuard peer %d server allowed IP", index+1))
			if prefixErr != nil {
				return nil, prefixErr
			}
			if prefix.Bits() != prefix.Addr().BitLen() {
				return nil, common.NewErrorf("WireGuard peer %d server allowed IP %s must use a host mask (/32 or /128)", index+1, value)
			}
			if _, exists := endpointAddresses[prefix.Addr()]; exists {
				return nil, common.NewErrorf("WireGuard peer %d address %s is already assigned to the server endpoint", index+1, value)
			}
			family := prefix.Addr().Is6()
			if seenFamily[family] {
				return nil, common.NewErrorf("WireGuard peer %d has more than one assigned IPv%d address", index+1, map[bool]int{false: 4, true: 6}[family])
			}
			seenFamily[family] = true
			if prefix.Addr().Is4() {
				if !tunnel4.IsValid() || !tunnel4.Contains(prefix.Addr()) {
					return nil, common.NewErrorf("WireGuard peer %d IPv4 address is outside the virtual network", index+1)
				}
				peer["assigned_ipv4"] = prefix.String()
			} else {
				if !tunnel6.IsValid() || !tunnel6.Contains(prefix.Addr()) {
					return nil, common.NewErrorf("WireGuard peer %d IPv6 address is outside the virtual network", index+1)
				}
				peer["assigned_ipv6"] = prefix.String()
			}
			for _, existing := range seenPrefixes {
				if existing.Overlaps(prefix) {
					return nil, common.NewErrorf("WireGuard peer %d address %s overlaps another peer", index+1, value)
				}
			}
			seenPrefixes = append(seenPrefixes, prefix)
		}
		peer["server_allowed_ips"] = interfaceStrings(serverAllowed)
		peer["allowed_ips"] = interfaceStrings(serverAllowed)
		ownAddresses := make(map[netip.Addr]struct{}, len(serverAllowed))
		for _, value := range serverAllowed {
			if prefix, prefixErr := netip.ParsePrefix(value); prefixErr == nil {
				ownAddresses[prefix.Addr()] = struct{}{}
			}
		}

		include4 := boolValue(peer["include_ipv4"], tunnel4.IsValid())
		include6 := boolValue(peer["include_ipv6"], tunnel6.IsValid())
		if !include4 && !include6 {
			return nil, common.NewErrorf("WireGuard peer %d must include IPv4, IPv6, or both", index+1)
		}
		peer["include_ipv4"] = include4
		peer["include_ipv6"] = include6
		preset := stringValue(peer["client_route_preset"])
		if preset == "" {
			preset = "virtual_network"
			peer["client_route_preset"] = preset
		}
		clientAllowed := stringsValue(peer["client_allowed_ips"])
		if len(clientAllowed) == 0 {
			clientAllowed = stringsValue(root["default_client_allowed_ips"])
		}
		if len(clientAllowed) == 0 {
			if include4 && tunnel4.IsValid() {
				clientAllowed = append(clientAllowed, tunnel4.String())
			}
			if include6 && tunnel6.IsValid() {
				clientAllowed = append(clientAllowed, tunnel6.String())
			}
		}
		filteredAllowed := make([]string, 0, len(clientAllowed))
		for _, value := range clientAllowed {
			prefix, prefixErr := parsePrefix(value, fmt.Sprintf("WireGuard peer %d client AllowedIPs", index+1))
			if prefixErr != nil {
				return nil, prefixErr
			}
			if (prefix.Bits() == 0) && preset != "full_tunnel" {
				return nil, common.NewErrorf("WireGuard peer %d must explicitly select the full-tunnel preset before using %s", index+1, value)
			}
			if preset == "single_peer" {
				if prefix.Bits() != prefix.Addr().BitLen() {
					return nil, common.NewErrorf("WireGuard peer %d single-peer routes must use /32 or /128 host addresses", index+1)
				}
				if _, ownAddress := ownAddresses[prefix.Addr()]; ownAddress {
					return nil, common.NewErrorf("WireGuard peer %d single-peer route %s points back to the same client", index+1, value)
				}
			}
			if (prefix.Addr().Is4() && include4) || (prefix.Addr().Is6() && include6) {
				filteredAllowed = append(filteredAllowed, prefix.String())
			}
		}
		if len(filteredAllowed) == 0 {
			return nil, common.NewErrorf("WireGuard peer %d client AllowedIPs are empty after applying IP version choices", index+1)
		}
		peer["client_allowed_ips"] = interfaceStrings(filteredAllowed)
		peers[index] = peer
	}
	root["peers"] = peers
	return json.Marshal(root)
}

func mergeWireGuardSecrets(data json.RawMessage, oldEndpoint *model.Endpoint) (json.RawMessage, error) {
	var root map[string]interface{}
	if err := json.Unmarshal(data, &root); err != nil || stringValue(root["type"]) != "wireguard" || oldEndpoint == nil {
		return data, err
	}
	var oldRoot map[string]interface{}
	if err := json.Unmarshal(oldEndpoint.Options, &oldRoot); err != nil {
		return nil, err
	}
	var oldExt map[string]interface{}
	_ = json.Unmarshal(oldEndpoint.Ext, &oldExt)
	legacySecrets := map[string]string{}
	for _, raw := range listValue(oldExt["keys"]) {
		key := mapValue(raw)
		if key != nil {
			legacySecrets[stringValue(key["public_key"])] = stringValue(key["private_key"])
		}
	}
	for _, raw := range listValue(oldRoot["peers"]) {
		peer := mapValue(raw)
		if peer != nil && stringValue(peer["client_private_key"]) != "" {
			legacySecrets[stringValue(peer["public_key"])] = stringValue(peer["client_private_key"])
		}
	}
	for _, raw := range listValue(root["peers"]) {
		peer := mapValue(raw)
		if peer == nil || stringValue(peer["client_private_key"]) != "" {
			continue
		}
		if secret := legacySecrets[stringValue(peer["public_key"])]; secret != "" {
			peer["client_private_key"] = secret
		}
	}
	return json.Marshal(root)
}

func redactWireGuardSecrets(endpoint map[string]interface{}) {
	for _, raw := range listValue(endpoint["peers"]) {
		peer := mapValue(raw)
		if peer == nil {
			continue
		}
		if stringValue(peer["client_private_key"]) != "" {
			peer["client_private_key_set"] = true
		}
		delete(peer, "client_private_key")
	}
	ext := mapValue(endpoint["ext"])
	for _, raw := range listValue(ext["keys"]) {
		key := mapValue(raw)
		if key != nil {
			delete(key, "private_key")
		}
	}
}

func syncWireGuardManagedRoute(tx *gorm.DB, endpoint *model.Endpoint) error {
	if endpoint == nil || endpoint.Type != "wireguard" {
		if endpoint != nil {
			return tx.Where("endpoint_tag = ?", endpoint.Tag).Delete(&model.ManagedRouteRule{}).Error
		}
		return nil
	}
	var options map[string]interface{}
	if err := json.Unmarshal(endpoint.Options, &options); err != nil {
		return err
	}
	key := "wireguard-peer-to-peer:" + endpoint.Tag
	if !boolValue(options["peer_to_peer_enabled"], false) {
		return tx.Where("managed_key = ?", key).Delete(&model.ManagedRouteRule{}).Error
	}
	rule := model.ManagedRouteRule{
		ManagedKey: key, EndpointTag: endpoint.Tag,
		IPv4CIDR: stringValue(options["tunnel_ipv4_cidr"]),
		IPv6CIDR: stringValue(options["tunnel_ipv6_cidr"]),
	}
	return tx.Where("managed_key = ?", key).Assign(rule).FirstOrCreate(&rule).Error
}

func (s *EndpointService) ExportWireGuardPeer(tag string, peerIndex int) (*WireGuardExport, error) {
	var endpoint model.Endpoint
	if err := database.GetDB().Where("tag = ? AND type = ?", tag, "wireguard").First(&endpoint).Error; err != nil {
		return nil, err
	}
	var root map[string]interface{}
	if err := json.Unmarshal(endpoint.Options, &root); err != nil {
		return nil, err
	}
	peers := listValue(root["peers"])
	if peerIndex < 0 || peerIndex >= len(peers) {
		return nil, common.NewError("WireGuard peer was not found")
	}
	peer := mapValue(peers[peerIndex])
	if peer == nil {
		return nil, common.NewError("WireGuard peer is invalid")
	}
	var ext map[string]interface{}
	_ = json.Unmarshal(endpoint.Ext, &ext)
	clientPrivateKey := stringValue(peer["client_private_key"])
	if clientPrivateKey == "" {
		for _, raw := range listValue(ext["keys"]) {
			key := mapValue(raw)
			if key != nil && stringValue(key["public_key"]) == stringValue(peer["public_key"]) {
				clientPrivateKey = stringValue(key["private_key"])
				break
			}
		}
	}
	if clientPrivateKey == "" {
		return nil, common.NewError("client private key is unavailable; generate a new key for this peer")
	}
	serverPublicKey := stringValue(ext["public_key"])
	if serverPublicKey == "" {
		privateKey, err := wgtypes.ParseKey(stringValue(root["private_key"]))
		if err != nil {
			return nil, common.NewError("WireGuard server public key is unavailable")
		}
		serverPublicKey = privateKey.PublicKey().String()
	}
	host := stringValue(root["advertised_endpoint_host"])
	port := intValue(root["advertised_endpoint_port"])
	if host == "" || port < 1 || port > 65535 {
		return nil, common.NewError("configure the client endpoint host and port before exporting")
	}

	include4 := boolValue(peer["include_ipv4"], true)
	include6 := boolValue(peer["include_ipv6"], true)
	addresses := make([]string, 0, 2)
	for _, value := range []string{stringValue(peer["assigned_ipv4"]), stringValue(peer["assigned_ipv6"])} {
		if value == "" {
			continue
		}
		prefix, err := netip.ParsePrefix(value)
		if err == nil && ((prefix.Addr().Is4() && include4) || (prefix.Addr().Is6() && include6)) {
			addresses = append(addresses, prefix.String())
		}
	}
	if len(addresses) == 0 {
		for _, value := range stringsValue(peer["allowed_ips"]) {
			prefix, err := netip.ParsePrefix(value)
			if err == nil && ((prefix.Addr().Is4() && include4) || (prefix.Addr().Is6() && include6)) {
				addresses = append(addresses, prefix.String())
			}
		}
	}
	allowed := stringsValue(peer["client_allowed_ips"])
	if len(allowed) == 0 {
		allowed = stringsValue(root["default_client_allowed_ips"])
	}
	if len(allowed) == 0 {
		for _, value := range []string{stringValue(root["tunnel_ipv4_cidr"]), stringValue(root["tunnel_ipv6_cidr"])} {
			if value != "" {
				allowed = append(allowed, value)
			}
		}
	}
	filteredAllowed := make([]string, 0, len(allowed))
	for _, value := range allowed {
		prefix, err := netip.ParsePrefix(value)
		if err == nil && ((prefix.Addr().Is4() && include4) || (prefix.Addr().Is6() && include6)) {
			filteredAllowed = append(filteredAllowed, prefix.String())
		}
	}
	if len(addresses) == 0 || len(filteredAllowed) == 0 {
		return nil, common.NewError("client addresses and AllowedIPs must be configured before exporting")
	}
	dns := stringsValue(peer["client_dns"])
	if len(dns) == 0 {
		dns = stringsValue(root["default_client_dns"])
	}
	if len(dns) == 0 {
		dns = stringsValue(ext["dns"])
	}
	mtu := intValue(peer["client_mtu"])
	if mtu == 0 {
		mtu = intValue(root["default_client_mtu"])
	}
	keepalive := intValue(peer["client_keepalive"])
	if keepalive == 0 {
		keepalive = intValue(root["default_client_keepalive"])
	}

	name := stringValue(peer["name"])
	if name == "" {
		name = fmt.Sprintf("Peer %d", peerIndex+1)
	}
	var config strings.Builder
	config.WriteString("[Interface]\nPrivateKey = " + clientPrivateKey + "\n")
	config.WriteString("Address = " + strings.Join(addresses, ", ") + "\n")
	if len(dns) > 0 {
		config.WriteString("DNS = " + strings.Join(dns, ", ") + "\n")
	}
	if mtu > 0 {
		config.WriteString(fmt.Sprintf("MTU = %d\n", mtu))
	}
	config.WriteString("\n[Peer]\nPublicKey = " + serverPublicKey + "\n")
	if psk := stringValue(peer["pre_shared_key"]); psk != "" {
		config.WriteString("PresharedKey = " + psk + "\n")
	}
	config.WriteString("AllowedIPs = " + strings.Join(filteredAllowed, ", ") + "\n")
	config.WriteString("Endpoint = " + net.JoinHostPort(strings.Trim(host, "[]"), strconv.Itoa(port)) + "\n")
	if keepalive > 0 {
		config.WriteString(fmt.Sprintf("PersistentKeepalive = %d\n", keepalive))
	}
	filename := filepath.Base(endpoint.Tag + "_" + strings.NewReplacer("/", "_", "\\", "_", " ", "_").Replace(name) + ".conf")
	return &WireGuardExport{Name: name, Filename: filename, Config: config.String()}, nil
}
