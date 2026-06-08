package storage

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"
	"time"

	"github.com/aliyun/aliyun-oss-go-sdk/oss"
	"go.uber.org/zap"

	"github.com/e2b-dev/infra/packages/shared/pkg/env"
	"github.com/e2b-dev/infra/packages/shared/pkg/logger"
)

// ----------------------------------------------------------------------------
// AlibabaCloud OSS storage backend
//
// Design choice — why not use awsStorage + S3-compatible endpoint:
//
//	  AlibabaCloud OSS exposes an S3-compatible API (v1 signature), but is not fully
//	  compatible with AWS SDK v2's default SigV4: multipart upload / list pagination /
//	  metadata header prefix (x-oss-meta- vs x-amz-meta-) all produce 400/403.
//	  Using aliyun-oss-go-sdk with native OSS v1 signature is the most stable approach.
//
// Required environment variables:
//
//	  ALIBABA_CLOUD_REGION                e.g. cn-hangzhou
//	  ALIBABA_CLOUD_ACCESS_KEY_ID         (or ALIBABA_CLOUD_ACCESS_KEY_ID)
//	  ALIBABA_CLOUD_ACCESS_KEY_SECRET     (or ALIBABA_CLOUD_ACCESS_KEY_SECRET)
//	  ALIBABA_CLOUD_OSS_ENDPOINT          e.g. https://oss-cn-hangzhou.aliyuncs.com
//	                                  (leave empty to auto-compose from region; use -internal for VPC)
//
// Integration with GetStorageProvider:
//
//	  Add a case in storage.go switch: case AlibabaCloudStorageProvider: return newAlibabaCloudStorage(...)
//	  And add to the constants:
//	     AlibabaCloudStorageProvider Provider = "AlibabaCloudBucket"
//
// ----------------------------------------------------------------------------

const (
	alibabaCloudOperationTimeout = 5 * time.Second
	alibabaCloudWriteTimeout     = 30 * time.Second
	alibabaCloudReadTimeout      = 15 * time.Second

	envAlibabaCloudOSSEndpoint     = "ALIBABA_CLOUD_OSS_ENDPOINT"
	envAlibabaCloudRegion          = "ALIBABA_CLOUD_REGION"
	envAlibabaCloudAccessKeyID     = "ALIBABA_CLOUD_ACCESS_KEY_ID"
	envAlibabaCloudAccessKeySecret = "ALIBABA_CLOUD_ACCESS_KEY_SECRET"
)

type alibabaCloudStorage struct {
	client     *oss.Client
	bucket     *oss.Bucket
	bucketName string
}

var _ StorageProvider = (*alibabaCloudStorage)(nil)

type alibabaCloudObject struct {
	bucket     *oss.Bucket
	bucketName string
	path       string
}

var (
	_ Seekable = (*alibabaCloudObject)(nil)
	_ Blob     = (*alibabaCloudObject)(nil)
)

func newAlibabaCloudStorage(_ context.Context, bucketName string) (*alibabaCloudStorage, error) {
	endpoint := env.GetEnv(envAlibabaCloudOSSEndpoint, "")
	if endpoint == "" {
		region := env.GetEnv(envAlibabaCloudRegion, "")
		if region == "" {
			return nil, errors.New("ALIBABA_CLOUD_REGION must be set when ALIBABA_CLOUD_OSS_ENDPOINT is empty")
		}
		// Recommended to use -internal endpoint within VPC for zero public traffic
		endpoint = fmt.Sprintf("https://oss-%s-internal.aliyuncs.com", region)
	}

	accessKeyID := env.GetEnv(envAlibabaCloudAccessKeyID, "")
	accessKeySecret := env.GetEnv(envAlibabaCloudAccessKeySecret, "")
	if accessKeyID == "" || accessKeySecret == "" {
		return nil, errors.New("ALIBABA_CLOUD_ACCESS_KEY_ID / ALIBABA_CLOUD_ACCESS_KEY_SECRET must be set")
	}

	client, err := oss.New(endpoint, accessKeyID, accessKeySecret)
	if err != nil {
		return nil, fmt.Errorf("failed to construct OSS client: %w", err)
	}

	bucket, err := client.Bucket(bucketName)
	if err != nil {
		return nil, fmt.Errorf("failed to bind OSS bucket %q: %w", bucketName, err)
	}

	return &alibabaCloudStorage{
		client:     client,
		bucket:     bucket,
		bucketName: bucketName,
	}, nil
}

func (s *alibabaCloudStorage) GetDetails() string {
	return fmt.Sprintf("[AlibabaCloud OSS Storage, bucket set to %s]", s.bucketName)
}

func (s *alibabaCloudStorage) DeleteObjectsWithPrefix(ctx context.Context, prefix string) error {
	ctx, cancel := context.WithTimeout(ctx, alibabaCloudOperationTimeout)
	defer cancel()

	// OSS ListObjectsV2 has a max of 1000 per call; pagination via marker needed for more.
	// For now we handle up to 1000 in a single pass.
	listResp, err := s.bucket.ListObjectsV2(oss.Prefix(prefix), oss.MaxKeys(1000))
	if err != nil {
		return fmt.Errorf("failed to list OSS objects with prefix %q: %w", prefix, err)
	}

	if len(listResp.Objects) == 0 {
		logger.L().Warn(ctx, "No objects found to delete with the given prefix",
			zap.String("prefix", prefix), zap.String("bucket", s.bucketName))
		return nil
	}

	keys := make([]string, 0, len(listResp.Objects))
	for _, obj := range listResp.Objects {
		keys = append(keys, obj.Key)
	}

	resp, err := s.bucket.DeleteObjects(keys, oss.DeleteObjectsQuiet(true))
	if err != nil {
		return fmt.Errorf("failed to delete OSS objects: %w", err)
	}
	if len(resp.DeletedObjects) > 0 {
		// With quiet=true, only failure items are returned; DeletedObjects should be empty on success
		var sb strings.Builder
		for _, k := range resp.DeletedObjects {
			fmt.Fprintf(&sb, "%s; ", k)
		}
		return errors.New("partial OSS delete failures: " + sb.String())
	}

	return nil
}

func (s *alibabaCloudStorage) UploadSignedURL(_ context.Context, path string, ttl time.Duration) (string, error) {
	url, err := s.bucket.SignURL(path, oss.HTTPPut, int64(ttl.Seconds()))
	if err != nil {
		return "", fmt.Errorf("failed to presign PUT URL for %q: %w", path, err)
	}
	return url, nil
}

func (s *alibabaCloudStorage) OpenSeekable(_ context.Context, path string, _ SeekableObjectType) (Seekable, error) {
	return &alibabaCloudObject{
		bucket:     s.bucket,
		bucketName: s.bucketName,
		path:       path,
	}, nil
}

func (s *alibabaCloudStorage) OpenBlob(_ context.Context, path string, _ ObjectType) (Blob, error) {
	return &alibabaCloudObject{
		bucket:     s.bucket,
		bucketName: s.bucketName,
		path:       path,
	}, nil
}

// ----------------------------- Object level ---------------------------------

func (o *alibabaCloudObject) WriteTo(ctx context.Context, dst io.Writer) (int64, error) {
	ctx, cancel := context.WithTimeout(ctx, alibabaCloudReadTimeout)
	defer cancel()

	body, err := o.bucket.GetObject(o.path)
	if err != nil {
		if isOSSNoSuchKey(err) {
			return 0, ErrObjectNotExist
		}
		return 0, err
	}
	defer body.Close()

	return io.Copy(dst, body)
}

func (o *alibabaCloudObject) StoreFile(ctx context.Context, path string, opts ...PutOption) (*FrameTable, [32]byte, error) {
	p := ApplyPutOptions(opts)
	if CompressConfigFromOpts(p).IsCompressionEnabled() {
		return nil, [32]byte{}, errors.New("compressed uploads are not supported on AlibabaCloud OSS (builds target GCP only)")
	}

	ctx, cancel := context.WithTimeout(ctx, alibabaCloudWriteTimeout)
	defer cancel()

	f, err := os.Open(path)
	if err != nil {
		return nil, [32]byte{}, fmt.Errorf("failed to open file %s: %w", path, err)
	}
	defer f.Close()

	fi, _ := f.Stat()
	var size int64
	if fi != nil {
		size = fi.Size()
	}

	// Use multipart for large files: 10MB parts, 8 concurrent routines (equivalent to AWS uploader)
	const partSize = 10 * 1024 * 1024
	if size > partSize {
		if err := o.bucket.UploadFile(o.path, path, partSize, oss.Routines(8)); err != nil {
			return nil, [32]byte{}, fmt.Errorf("OSS multipart upload failed: %w", err)
		}
	} else {
		if err := o.bucket.PutObject(o.path, f, ossMetadataOptions(p.Metadata)...); err != nil {
			return nil, [32]byte{}, fmt.Errorf("OSS PutObject failed: %w", err)
		}
	}

	logger.L().Debug(ctx, "Uploaded file to OSS",
		zap.String("bucket", o.bucketName),
		zap.String("object", o.path),
		zap.String("source", path),
		zap.Int64("size_uncompressed", size),
		zap.String("compression", "none"),
	)

	return nil, [32]byte{}, nil
}

func (o *alibabaCloudObject) Put(ctx context.Context, data []byte, opts ...PutOption) error {
	ctx, cancel := context.WithTimeout(ctx, alibabaCloudWriteTimeout)
	defer cancel()
	_ = ctx

	p := ApplyPutOptions(opts)
	return o.bucket.PutObject(o.path, bytes.NewReader(data), ossMetadataOptions(p.Metadata)...)
}

func (o *alibabaCloudObject) OpenRangeReader(ctx context.Context, off, length int64, frameTable *FrameTable) (io.ReadCloser, error) {
	if frameTable.IsCompressed() {
		return nil, errors.New("compressed reads are not supported on AlibabaCloud OSS")
	}

	body, err := o.bucket.GetObject(o.path, oss.Range(off, off+length-1))
	if err != nil {
		if isOSSNoSuchKey(err) {
			return nil, ErrObjectNotExist
		}
		return nil, fmt.Errorf("failed to create OSS range reader for %q: %w", o.path, err)
	}
	return body, nil
}

func (o *alibabaCloudObject) Size(ctx context.Context) (int64, error) {
	ctx, cancel := context.WithTimeout(ctx, alibabaCloudOperationTimeout)
	defer cancel()
	_ = ctx

	meta, err := o.bucket.GetObjectMeta(o.path)
	if err != nil {
		if isOSSNoSuchKey(err) {
			return 0, ErrObjectNotExist
		}
		return 0, err
	}

	cl := meta.Get("Content-Length")
	if cl == "" {
		return 0, errors.New("OSS GetObjectMeta did not return Content-Length")
	}

	var size int64
	if _, err := fmt.Sscanf(cl, "%d", &size); err != nil {
		return 0, fmt.Errorf("invalid Content-Length %q: %w", cl, err)
	}
	return size, nil
}

func (o *alibabaCloudObject) Exists(ctx context.Context) (bool, error) {
	_, err := o.Size(ctx)
	return err == nil, ignoreNotExists(err)
}

func (o *alibabaCloudObject) Delete(_ context.Context) error {
	return o.bucket.DeleteObject(o.path)
}

// ----------------------------- helpers --------------------------------------

func ossMetadataOptions(meta map[string]string) []oss.Option {
	if len(meta) == 0 {
		return nil
	}
	out := make([]oss.Option, 0, len(meta))
	for k, v := range meta {
		// SDK auto-prepends x-oss-meta- prefix
		out = append(out, oss.Meta(k, v))
	}
	return out
}

func isOSSNoSuchKey(err error) bool {
	if err == nil {
		return false
	}
	var srvErr oss.ServiceError
	if errors.As(err, &srvErr) {
		return srvErr.StatusCode == 404 || srvErr.Code == "NoSuchKey"
	}
	// Fallback: message matching (older SDK versions may lack structured error types)
	return strings.Contains(err.Error(), "NoSuchKey") || strings.Contains(err.Error(), "404")
}
