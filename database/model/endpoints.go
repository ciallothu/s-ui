package model

import (
	"encoding/json"
)

// ManagedRouteRule stores routes owned by S-UI. These rules are injected into
// the generated sing-box configuration and never mixed into the user's route
// JSON, so disabling a feature cannot delete a user-authored rule.
type ManagedRouteRule struct {
	Id          uint   `json:"id" gorm:"primaryKey;autoIncrement"`
	ManagedKey  string `json:"managedKey" gorm:"uniqueIndex;not null"`
	EndpointTag string `json:"endpointTag" gorm:"index;not null"`
	IPv4CIDR    string `json:"ipv4Cidr"`
	IPv6CIDR    string `json:"ipv6Cidr"`
}

type Endpoint struct {
	Id      uint            `json:"id" form:"id" gorm:"primaryKey;autoIncrement"`
	Type    string          `json:"type" form:"type"`
	Tag     string          `json:"tag" form:"tag" gorm:"unique"`
	Options json.RawMessage `json:"-" form:"-"`
	Ext     json.RawMessage `json:"ext" form:"ext"`
}

func (o *Endpoint) UnmarshalJSON(data []byte) error {
	var err error
	var raw map[string]interface{}
	if err = json.Unmarshal(data, &raw); err != nil {
		return err
	}

	// Extract fixed fields and store the rest in Options
	if val, exists := raw["id"].(float64); exists {
		o.Id = uint(val)
	}
	delete(raw, "id")
	o.Type, _ = raw["type"].(string)
	delete(raw, "type")
	o.Tag = raw["tag"].(string)
	delete(raw, "tag")
	o.Ext, _ = json.MarshalIndent(raw["ext"], "", "  ")
	delete(raw, "ext")

	// Remaining fields
	o.Options, err = json.MarshalIndent(raw, "", "  ")
	return err
}

// MarshalJSON customizes marshalling
func (o Endpoint) MarshalJSON() ([]byte, error) {
	// Combine fixed fields and dynamic fields into one map
	combined := make(map[string]interface{})
	switch o.Type {
	case "warp":
		combined["type"] = "wireguard"
	default:
		combined["type"] = o.Type
	}
	combined["tag"] = o.Tag

	if o.Options != nil {
		var restFields map[string]interface{}
		if err := json.Unmarshal(o.Options, &restFields); err != nil {
			return nil, err
		}
		if o.Type == "wireguard" {
			restFields = wireGuardRuntimeOptions(restFields)
		}

		for k, v := range restFields {
			combined[k] = v
		}
	}

	return json.Marshal(combined)
}

var wireGuardEndpointMetadataKeys = []string{
	"wireguard_schema", "tunnel_ipv4_cidr", "tunnel_ipv6_cidr",
	"advertised_endpoint_host", "advertised_endpoint_port", "peer_to_peer_enabled",
	"default_client_allowed_ips", "default_client_dns", "default_client_mtu",
	"default_client_keepalive",
}

var wireGuardPeerMetadataKeys = []string{
	"name", "peer_mode", "client_private_key", "client_private_key_set", "client_public_key",
	"assigned_ipv4", "assigned_ipv6", "server_allowed_ips", "client_allowed_ips",
	"client_dns", "client_mtu", "client_keepalive", "client_route_preset",
	"include_ipv4", "include_ipv6", "static_remote_address", "static_remote_port",
}

// wireGuardRuntimeOptions removes S-UI export/editor metadata before the
// object is handed to sing-box v1.13.12. Only fields accepted by
// option.WireGuardEndpointOptions and option.WireGuardPeer remain.
func wireGuardRuntimeOptions(options map[string]interface{}) map[string]interface{} {
	for _, key := range wireGuardEndpointMetadataKeys {
		delete(options, key)
	}
	peers, _ := options["peers"].([]interface{})
	for index, rawPeer := range peers {
		peer, ok := rawPeer.(map[string]interface{})
		if !ok {
			continue
		}
		mode, _ := peer["peer_mode"].(string)
		if serverAllowed, ok := peer["server_allowed_ips"].([]interface{}); ok && len(serverAllowed) > 0 {
			peer["allowed_ips"] = serverAllowed
		}
		if mode == "roaming_client" || mode == "" {
			delete(peer, "address")
			delete(peer, "port")
		} else {
			if address, ok := peer["static_remote_address"].(string); ok && address != "" {
				peer["address"] = address
			}
			if port, ok := peer["static_remote_port"]; ok {
				peer["port"] = port
			}
		}
		for _, key := range wireGuardPeerMetadataKeys {
			delete(peer, key)
		}
		peers[index] = peer
	}
	options["peers"] = peers
	return options
}
