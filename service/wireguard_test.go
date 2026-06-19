package service

import (
	"encoding/json"
	"path/filepath"
	"strings"
	"testing"

	"github.com/alireza0/s-ui/database"
	"github.com/alireza0/s-ui/database/model"

	"golang.zx2c4.com/wireguard/wgctrl/wgtypes"
)

func testWireGuardData(t *testing.T) map[string]interface{} {
	t.Helper()
	serverKey, err := wgtypes.GeneratePrivateKey()
	if err != nil {
		t.Fatal(err)
	}
	clientKey, err := wgtypes.GeneratePrivateKey()
	if err != nil {
		t.Fatal(err)
	}
	return map[string]interface{}{
		"id": 0, "type": "wireguard", "tag": "wireguard-test", "wireguard_schema": 2,
		"address":          []string{"10.66.66.1/32", "fd66:66:66::1/128"},
		"tunnel_ipv4_cidr": "10.66.66.0/24", "tunnel_ipv6_cidr": "fd66:66:66::/64",
		"private_key": serverKey.String(), "listen_port": 20522,
		"advertised_endpoint_host": "vpn.example.com", "advertised_endpoint_port": 20522,
		"peer_to_peer_enabled":       true,
		"default_client_allowed_ips": []string{"10.66.66.0/24", "fd66:66:66::/64"},
		"default_client_dns":         []string{"10.66.66.1"}, "default_client_mtu": 1420, "default_client_keepalive": 25,
		"peers": []interface{}{map[string]interface{}{
			"name": "Laptop", "peer_mode": "roaming_client", "public_key": clientKey.PublicKey().String(),
			"client_private_key": clientKey.String(), "assigned_ipv4": "10.66.66.2/32", "assigned_ipv6": "fd66:66:66::2/128",
			"client_route_preset": "virtual_network", "client_allowed_ips": []string{"10.66.66.0/24", "fd66:66:66::/64"},
			"include_ipv4": true, "include_ipv6": true,
		}},
		"ext": map[string]interface{}{"public_key": serverKey.PublicKey().String(), "keys": []interface{}{}},
	}
}

func TestNormalizeWireGuardSeparatesServerAndClientAllowedIPs(t *testing.T) {
	data, err := json.Marshal(testWireGuardData(t))
	if err != nil {
		t.Fatal(err)
	}
	normalized, err := normalizeAndValidateWireGuard(data)
	if err != nil {
		t.Fatal(err)
	}
	var root map[string]interface{}
	if err = json.Unmarshal(normalized, &root); err != nil {
		t.Fatal(err)
	}
	peer := mapValue(listValue(root["peers"])[0])
	if got := strings.Join(stringsValue(peer["server_allowed_ips"]), ","); got != "10.66.66.2/32,fd66:66:66::2/128" {
		t.Fatalf("unexpected server allowed IPs: %s", got)
	}
	if got := strings.Join(stringsValue(peer["client_allowed_ips"]), ","); got != "10.66.66.0/24,fd66:66:66::/64" {
		t.Fatalf("unexpected client AllowedIPs: %s", got)
	}
}

func TestNormalizeWireGuardRejectsEndpointNetworkMask(t *testing.T) {
	data := testWireGuardData(t)
	data["address"] = []string{"10.66.66.1/24", "fd66:66:66::1/128"}
	raw, _ := json.Marshal(data)
	if _, err := normalizeAndValidateWireGuard(raw); err == nil || !strings.Contains(err.Error(), "/32") {
		t.Fatalf("expected host-mask validation error, got %v", err)
	}
}

func TestNormalizeWireGuardRequiresExplicitFullTunnel(t *testing.T) {
	data := testWireGuardData(t)
	peer := mapValue(listValue(data["peers"])[0])
	peer["client_allowed_ips"] = []string{"0.0.0.0/0", "::/0"}
	raw, _ := json.Marshal(data)
	if _, err := normalizeAndValidateWireGuard(raw); err == nil || !strings.Contains(err.Error(), "full-tunnel") {
		t.Fatalf("expected full-tunnel validation error, got %v", err)
	}
	peer["client_route_preset"] = "full_tunnel"
	raw, _ = json.Marshal(data)
	if _, err := normalizeAndValidateWireGuard(raw); err != nil {
		t.Fatalf("explicit full tunnel should be accepted: %v", err)
	}
}

func TestNormalizeWireGuardRejectsPeerAddressOwnedByEndpoint(t *testing.T) {
	data := testWireGuardData(t)
	peer := mapValue(listValue(data["peers"])[0])
	peer["assigned_ipv4"] = "10.66.66.1/32"
	peer["assigned_ipv6"] = ""
	peer["client_allowed_ips"] = []string{"10.66.66.0/24"}
	peer["include_ipv6"] = false
	raw, _ := json.Marshal(data)
	if _, err := normalizeAndValidateWireGuard(raw); err == nil || !strings.Contains(err.Error(), "server endpoint") {
		t.Fatalf("expected endpoint ownership validation error, got %v", err)
	}
}

func TestNormalizeWireGuardSinglePeerRouteCannotPointToSelf(t *testing.T) {
	data := testWireGuardData(t)
	peer := mapValue(listValue(data["peers"])[0])
	peer["client_route_preset"] = "single_peer"
	peer["client_allowed_ips"] = []string{"10.66.66.2/32"}
	raw, _ := json.Marshal(data)
	if _, err := normalizeAndValidateWireGuard(raw); err == nil || !strings.Contains(err.Error(), "same client") {
		t.Fatalf("expected single-peer self-route validation error, got %v", err)
	}
}

func TestWireGuardRuntimeJSONStripsEditorMetadata(t *testing.T) {
	raw, _ := json.Marshal(testWireGuardData(t))
	var endpoint model.Endpoint
	if err := endpoint.UnmarshalJSON(raw); err != nil {
		t.Fatal(err)
	}
	runtimeJSON, err := endpoint.MarshalJSON()
	if err != nil {
		t.Fatal(err)
	}
	text := string(runtimeJSON)
	for _, forbidden := range []string{"client_allowed_ips", "client_private_key", "advertised_endpoint_host", "peer_to_peer_enabled"} {
		if strings.Contains(text, forbidden) {
			t.Fatalf("runtime JSON leaked editor metadata %q: %s", forbidden, text)
		}
	}
	if strings.Contains(text, `"address":"`) {
		t.Fatalf("roaming peer must not contain a static remote address: %s", text)
	}
}

func TestWireGuardExportUsesAdvertisedEndpointAndSplitTunnel(t *testing.T) {
	if err := database.InitDB(filepath.Join(t.TempDir(), "s-ui.db")); err != nil {
		t.Fatal(err)
	}
	raw, _ := json.Marshal(testWireGuardData(t))
	var endpoint model.Endpoint
	if err := endpoint.UnmarshalJSON(raw); err != nil {
		t.Fatal(err)
	}
	if err := database.GetDB().Create(&endpoint).Error; err != nil {
		t.Fatal(err)
	}
	result, err := (&EndpointService{}).ExportWireGuardPeer(endpoint.Tag, 0)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(result.Config, "Endpoint = vpn.example.com:20522") {
		t.Fatalf("export did not use the advertised endpoint: %s", result.Config)
	}
	if !strings.Contains(result.Config, "AllowedIPs = 10.66.66.0/24, fd66:66:66::/64") {
		t.Fatalf("export did not use split-tunnel routes: %s", result.Config)
	}
	if strings.Contains(result.Config, "0.0.0.0/0") {
		t.Fatalf("split-tunnel export unexpectedly contains a default route: %s", result.Config)
	}
}

func TestManagedWireGuardRouteDoesNotDuplicateUserRule(t *testing.T) {
	if err := database.InitDB(filepath.Join(t.TempDir(), "s-ui.db")); err != nil {
		t.Fatal(err)
	}
	rule := model.ManagedRouteRule{
		ManagedKey: "wireguard-peer-to-peer:wireguard-test", EndpointTag: "wireguard-test",
		IPv4CIDR: "10.66.66.0/24", IPv6CIDR: "fd66:66:66::/64",
	}
	if err := database.GetDB().Create(&rule).Error; err != nil {
		t.Fatal(err)
	}
	raw := json.RawMessage(`{"rules":[{"inbound":["wireguard-test"],"ip_cidr":["10.66.66.0/24","fd66:66:66::/64"],"action":"route","outbound":"wireguard-test"}]}`)
	result, err := injectManagedRoutes(database.GetDB(), raw)
	if err != nil {
		t.Fatal(err)
	}
	var route map[string]interface{}
	if err = json.Unmarshal(result, &route); err != nil {
		t.Fatal(err)
	}
	if got := len(listValue(route["rules"])); got != 1 {
		t.Fatalf("managed route duplicated an equivalent user rule: %d", got)
	}
}

func TestAuditRedactionHidesWireGuardSecrets(t *testing.T) {
	redacted := redactChangeData(json.RawMessage(`{"private_key":"private","pre_shared_key":"psk","token":"token","public_key":"public"}`))
	var value map[string]interface{}
	if err := json.Unmarshal(redacted, &value); err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"private_key", "pre_shared_key", "token"} {
		if value[key] != "[redacted]" {
			t.Fatalf("audit data did not redact %s: %s", key, string(redacted))
		}
	}
	if value["public_key"] != "public" {
		t.Fatalf("non-secret public key was unexpectedly redacted: %s", string(redacted))
	}
}
