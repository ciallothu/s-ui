package service

import (
	"net/http/httptest"
	"testing"
)

func TestDetectRequestOriginPrefersBrowserOrigin(t *testing.T) {
	request := httptest.NewRequest("POST", "http://127.0.0.1/app/api/passkey-register-begin", nil)
	request.Header.Set("Origin", "https://panel.example.com")
	request.Header.Set("X-Forwarded-Host", "internal.example.net")
	if got := detectRequestOrigin(request); got != "https://panel.example.com" {
		t.Fatalf("origin = %q", got)
	}
	if got := detectRequestRPID(request, detectRequestOrigin(request)); got != "panel.example.com" {
		t.Fatalf("RP ID = %q", got)
	}
}

func TestDetectRequestOriginFromReverseProxy(t *testing.T) {
	request := httptest.NewRequest("POST", "http://127.0.0.1/app/api/passkey-register-begin", nil)
	request.Header.Set("Forwarded", `for=192.0.2.1;proto=https;host="panel.example.com:8443"`)
	if got := detectRequestOrigin(request); got != "https://panel.example.com:8443" {
		t.Fatalf("origin = %q", got)
	}
	if got := detectRequestRPID(request, detectRequestOrigin(request)); got != "panel.example.com" {
		t.Fatalf("RP ID = %q", got)
	}
}
