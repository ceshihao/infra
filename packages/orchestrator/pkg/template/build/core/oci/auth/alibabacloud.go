package auth

import (
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"strings"

	cr20181201 "github.com/alibabacloud-go/cr-20181201/v2/client"
	openapi "github.com/alibabacloud-go/darabonba-openapi/v2/client"
	"github.com/alibabacloud-go/tea/tea"
	"github.com/google/go-containerregistry/pkg/authn"
	"github.com/google/go-containerregistry/pkg/v1/remote"

	templatemanager "github.com/e2b-dev/infra/packages/shared/pkg/grpc/template-manager"
)

// ----------------------------------------------------------------------------
// AlibabaCloudACRAuthProvider — Alibaba Cloud Container Registry (ACR) Enterprise Edition auth
//
// Differences from AWS ECR:
//   1) GetAuthorizationToken credential expires in 1 hour (ECR is 12h) → cannot cache at
//      process startup; must refresh before every image pull/push or use instance-level
//      long-lived token with short-lived session refresh. This implementation refreshes
//      on every GetAuthOption call for simplicity and reliability.
//   2) Enterprise Edition requires instance_id (cr-cn-xxx); Personal Edition has no
//      instance concept and only supports fixed username/password (not recommended for prod).
//   3) Enterprise Edition is VPC-only by default; public access requires enabling the
//      "public network access" toggle in the ACR console.
//
// Proto extension (packages/shared/pkg/grpc/template-manager.proto) needs:
//
//   message AlibabaCloudRegistry {
//     string access_key_id     = 1;
//     string access_key_secret = 2;
//     string region            = 3;          // e.g. cn-hangzhou
//     string instance_id       = 4;          // cr-cn-xxxx, required for Enterprise Edition
//   }
//   message FromImageRegistry {
//     oneof type {
//       AWSRegistry      aws      = 1;
//       GCPRegistry      gcp      = 2;
//       GeneralRegistry  general  = 3;
//       AlibabaCloudRegistry alibabacloud = 4;        // <- new
//     }
//   }
//
// Then add a new case in NewAuthProvider's switch:
//
//   case *templatemanager.FromImageRegistry_Alibabacloud:
//       return NewAlibabaCloudACRAuthProvider(auth.Alibabacloud)
// ----------------------------------------------------------------------------

// AlibabaCloudACRAuthProvider implements authentication for AlibabaCloud Container Registry (ACR EE).
type AlibabaCloudACRAuthProvider struct {
	registry *templatemanager.AlibabaCloudRegistry
}

// NewAlibabaCloudACRAuthProvider creates a new AlibabaCloud ACR auth provider.
func NewAlibabaCloudACRAuthProvider(registry *templatemanager.AlibabaCloudRegistry) *AlibabaCloudACRAuthProvider {
	return &AlibabaCloudACRAuthProvider{registry: registry}
}

// GetAuthOption returns the authentication option for AlibabaCloud ACR.
func (p *AlibabaCloudACRAuthProvider) GetAuthOption(_ context.Context) (remote.Option, error) {
	if p.registry == nil {
		return nil, errors.New("alibabacloud registry is nil")
	}
	if strings.TrimSpace(p.registry.GetInstanceId()) == "" {
		return nil, errors.New("alibabacloud ACR enterprise edition requires instance_id")
	}

	endpoint := fmt.Sprintf("cr.%s.aliyuncs.com", p.registry.GetRegion())
	cfg := &openapi.Config{
		AccessKeyId:     tea.String(p.registry.GetAccessKeyId()),
		AccessKeySecret: tea.String(p.registry.GetAccessKeySecret()),
		Endpoint:        tea.String(endpoint),
		RegionId:        tea.String(p.registry.GetRegion()),
	}

	client, err := cr20181201.NewClient(cfg)
	if err != nil {
		return nil, fmt.Errorf("failed to construct ACR client: %w", err)
	}

	resp, err := client.GetAuthorizationToken(&cr20181201.GetAuthorizationTokenRequest{
		InstanceId: tea.String(p.registry.GetInstanceId()),
	})
	if err != nil {
		return nil, fmt.Errorf("failed to get ACR authorization token: %w", err)
	}
	if resp == nil || resp.Body == nil {
		return nil, errors.New("empty response from ACR GetAuthorizationToken")
	}

	username := tea.StringValue(resp.Body.TempUsername)
	rawToken := tea.StringValue(resp.Body.AuthorizationToken)
	if username == "" || rawToken == "" {
		return nil, errors.New("ACR returned empty username or token")
	}

	// Some SDK versions return the token already base64-decoded, others still base64-encoded.
	// We uniformly attempt decoding here: if it fails, use rawToken as plaintext password.
	password := rawToken
	if decoded, err := base64.StdEncoding.DecodeString(rawToken); err == nil && len(decoded) > 0 {
		// Docker registry v2 temp credentials are typically plaintext (not user:pass encoded),
		// so use the decoded value directly as password.
		password = string(decoded)
	}

	return remote.WithAuth(&authn.Basic{
		Username: username,
		Password: password,
	}), nil
}
