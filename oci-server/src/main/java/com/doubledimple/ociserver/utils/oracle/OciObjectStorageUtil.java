package com.doubledimple.ociserver.utils.oracle;

import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.Collections;
import java.util.Map;
import java.util.HashMap;
import java.util.List;
import java.util.ArrayList;

import com.doubledimple.dao.entity.Tenant;
import com.oracle.bmc.auth.AuthenticationDetailsProvider;
import lombok.extern.slf4j.Slf4j;
import com.oracle.bmc.objectstorage.ObjectStorageClient;
import com.oracle.bmc.objectstorage.requests.*;
import com.oracle.bmc.objectstorage.responses.*;
import com.oracle.bmc.objectstorage.model.*;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import org.springframework.util.StringUtils;

import static com.doubledimple.ociserver.utils.oracle.OciUtils.getProvider;

/**
 * @version 1.0.0
 * @ClassName OCIObjectStorageUtil
 * @Description 对象存储
 * @Author doubleDimple
 * @Date 2025-04-02 17:23
 */
@Slf4j
public class OciObjectStorageUtil {

    public static final String BUCKET_NAME = "OCI_START_BUCKET";

    /**
    *  默认为禁止公共访问
    */
    public static final String DEFAULT_ACCESS_TYPE = "NoPublicAccess";

    public static final String INSTANCE_PASS_WORD_BUCKET_NAME = "INSTANCE_PASS_WORD_BUCKET";

    public static final String OBJECT_NAME_PATH_PREFIX = "OCI-START_";


    /**
     * 获取所有存储桶列表
     * @param tenant 身份验证提供程序
     * @return 存储桶列表
     */
    public static List<BucketSummary> listBuckets(Tenant tenant) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        String compartmentId = provider.getTenantId();
        try (ObjectStorageClient client = ObjectStorageClient.builder().build(provider)) {
            final String namespace = getNamespace(provider);
            ListBucketsRequest request = ListBucketsRequest.builder()
                    .namespaceName(namespace)
                    .compartmentId(compartmentId)
                    .fields(Collections.singletonList(ListBucketsRequest.Fields.Tags))
                    .build();

            ListBucketsResponse response = client.listBuckets(request);
            log.info("成功获取到 {} 个存储桶", response.getItems().size());
            return response.getItems();
        } catch (Exception e) {
            log.error("获取存储桶列表失败: {}", e.getMessage(), e);
            return new ArrayList<>();
        }
    }

    /**
     * 创建存储桶
     * @param tenant 身份验证提供程序
     * @param compartmentId 区间ID
     * @param publicAccessType 公共访问类型 (NoPublicAccess, ObjectRead, ObjectReadWithoutList)
     * @return 是否创建成功
     */
    public static boolean createBucket(Tenant tenant,
                                       String compartmentId,
                                       String publicAccessType) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        try (ObjectStorageClient client = ObjectStorageClient.builder().build(provider)) {
            // 设置存储桶的公共访问类型
            CreateBucketDetails.PublicAccessType accessType = CreateBucketDetails.PublicAccessType.NoPublicAccess;
            if ("ObjectRead".equalsIgnoreCase(publicAccessType)) {
                accessType = CreateBucketDetails.PublicAccessType.ObjectRead;
            } else if ("ObjectReadWithoutList".equalsIgnoreCase(publicAccessType)) {
                accessType = CreateBucketDetails.PublicAccessType.ObjectReadWithoutList;
            }

            CreateBucketDetails bucketDetails = CreateBucketDetails.builder()
                    .name(BUCKET_NAME)
                    .compartmentId(compartmentId)
                    .publicAccessType(accessType)
                    .build();

            CreateBucketRequest request = CreateBucketRequest.builder()
                    .namespaceName(getNamespace(provider))
                    .createBucketDetails(bucketDetails)
                    .build();

            CreateBucketResponse response = client.createBucket(request);
            log.info("成功创建存储桶: {}", BUCKET_NAME);
            return true;
        } catch (Exception e) {
            log.error("创建存储桶失败: {}", e.getMessage(), e);
            return false;
        }
    }

    /**
     * 上传对象到存储桶
     * @param tenant 身份验证提供程序
     * @param objectName 对象名称（在存储桶中的路径）
     * @param filePath 要上传的文件路径
     * @param contentType 内容类型（如"application/octet-stream", "text/plain"等）
     * @return 是否上传成功
     */
    public static boolean uploadObject(Tenant tenant,
                                       String objectName,
                                       String filePath,
                                       String contentType) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        try (ObjectStorageClient client = ObjectStorageClient.builder().build(provider)) {
            File file = new File(filePath);
            if (!file.exists()) {
                log.error("文件不存在: {}", filePath);
                return false;
            }

            // 设置上传对象的内容类型
            Map<String, String> metadata = new HashMap<>();
            if (contentType == null || contentType.isEmpty()) {
                contentType = "application/octet-stream";
            }

            try (InputStream fileStream = new FileInputStream(file)) {
                PutObjectRequest request = PutObjectRequest.builder()
                        .namespaceName(getNamespace(provider))
                        .bucketName(BUCKET_NAME)
                        .objectName(objectName)
                        .contentType(contentType)
                        .contentLength(file.length())
                        .putObjectBody(fileStream)
                        .opcMeta(metadata)
                        .build();

                client.putObject(request);
                log.info("成功上传文件到存储桶 {}/{}: 大小: {} bytes",
                        BUCKET_NAME, objectName, file.length());
                return true;
            }
        } catch (Exception e) {
            log.error("上传文件失败: {}", e.getMessage(), e);
            return false;
        }
    }

    /**
     * 下载对象
     * @param tenant 身份验证提供程序
     * @param objectName 对象名称
     * @param saveFilePath 保存文件的路径
     * @return 是否下载成功
     */
    public static boolean downloadObject(Tenant tenant,
                                         String objectName,
                                         String saveFilePath) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        try (ObjectStorageClient client = ObjectStorageClient.builder().build(provider)) {
            GetObjectRequest request = GetObjectRequest.builder()
                    .namespaceName(getNamespace(provider))
                    .bucketName(BUCKET_NAME)
                    .objectName(objectName)
                    .build();

            GetObjectResponse response = client.getObject(request);

            // 创建保存文件的目录（如果不存在）
            File saveDir = new File(saveFilePath).getParentFile();
            if (saveDir != null && !saveDir.exists()) {
                saveDir.mkdirs();
            }

            // 将对象内容保存到文件
            Files.copy(response.getInputStream(), Paths.get(saveFilePath));
            log.info("成功下载文件: {}", saveFilePath);
            return true;
        } catch (Exception e) {
            log.error("下载文件失败: {}", e.getMessage(), e);
            return false;
        }
    }

    /**
     * 列出存储桶中的对象
     * @param tenant 身份验证提供程序
     * @param namespaceName 命名空间名称
     * @param bucketName 存储桶名称
     * @param prefix 对象名称前缀（可选，用于过滤）
     * @return 对象列表
     */
    public static List<ObjectSummary> listObjects(Tenant tenant,
                                                  String namespaceName,
                                                  String bucketName,
                                                  String prefix) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        try (ObjectStorageClient client = ObjectStorageClient.builder().build(provider)) {
            ListObjectsRequest.Builder requestBuilder = ListObjectsRequest.builder()
                    .namespaceName(namespaceName)
                    .bucketName(bucketName);

            if (prefix != null && !prefix.isEmpty()) {
                requestBuilder.prefix(prefix);
            }

            ListObjectsResponse response = client.listObjects(requestBuilder.build());
            log.info("在存储桶 {} 中找到 {} 个对象", bucketName, response.getListObjects().getObjects().size());
            return response.getListObjects().getObjects();
        } catch (Exception e) {
            log.error("列出存储桶对象失败: {}", e.getMessage(), e);
            return new ArrayList<>();
        }
    }

    /**
     * 删除对象
     * @param tenant 身份验证提供程序
     * @param objectName 对象名称
     * @return 是否删除成功
     */
    public static boolean deleteObject(Tenant tenant,
                                       String objectName) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        final String namespace = getNamespace(provider);
        try (ObjectStorageClient client = ObjectStorageClient.builder().build(provider)) {
            DeleteObjectRequest request = DeleteObjectRequest.builder()
                    .namespaceName(namespace)
                    .bucketName(BUCKET_NAME)
                    .objectName(objectName)
                    .build();

            client.deleteObject(request);
            log.info("成功删除对象 {}/{}", BUCKET_NAME, objectName);
            return true;
        } catch (Exception e) {
            log.error("删除对象失败: {}", e.getMessage(), e);
            return false;
        }
    }

    /**
     * 获取命名空间
     * @param tenant 身份验证提供程序
     * @return 命名空间名称
     */
    public static String getNamespace(Tenant tenant) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        try (ObjectStorageClient client = ObjectStorageClient.builder().build(provider)) {
            GetNamespaceRequest request = GetNamespaceRequest.builder().build();
            String namespace = client.getNamespace(request).getValue();
            log.info("获取到命名空间: {}", namespace);
            return namespace;
        } catch (Exception e) {
            log.error("获取命名空间失败: {}", e.getMessage(), e);
            return null;
        }
    }

    /**
     * 生成预签名URL用于临时访问
     * @param tenant 身份验证提供程
     * @param objectName 对象名称
     * @param validityInSeconds URL有效期（秒）
     * @return 预签名URL
     */
    public static String generatePresignedUrl(Tenant tenant,
                                              String objectName,
                                              long validityInSeconds) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        try (ObjectStorageClient client = ObjectStorageClient.builder().build(provider)) {
            CreatePreauthenticatedRequestDetails details = CreatePreauthenticatedRequestDetails.builder()
                    .name("PAR-" + System.currentTimeMillis())
                    .objectName(objectName)
                    .accessType(CreatePreauthenticatedRequestDetails.AccessType.ObjectRead)
                    .timeExpires(new java.util.Date(System.currentTimeMillis() + validityInSeconds * 1000))
                    .build();

            CreatePreauthenticatedRequestRequest request = CreatePreauthenticatedRequestRequest.builder()
                    .namespaceName(getNamespace(provider))
                    .bucketName(BUCKET_NAME)
                    .createPreauthenticatedRequestDetails(details)
                    .build();

            CreatePreauthenticatedRequestResponse response = client.createPreauthenticatedRequest(request);

            // 构建完整的URL
            String baseUrl = client.getEndpoint();
            String parUrl = baseUrl + response.getPreauthenticatedRequest().getAccessUri();
            log.info("生成预签名URL: {}", parUrl);
            return parUrl;
        } catch (Exception e) {
            log.error("生成预签名URL失败: {}", e.getMessage(), e);
            return null;
        }
    }

    /**
     * 生成指定存储桶对象的预签名URL
     * @param tenant 身份验证提供程序
     * @param namespaceName 命名空间名称
     * @param bucketName 存储桶名称
     * @param objectName 对象名称
     * @param validityInSeconds URL有效期（秒）
     * @return 预签名URL
     */
    public static String generatePresignedUrlForBucket(Tenant tenant,
                                                       String namespaceName,
                                                       String bucketName,
                                                       String objectName,
                                                       long validityInSeconds) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        try (ObjectStorageClient client = ObjectStorageClient.builder().build(provider)) {
            CreatePreauthenticatedRequestDetails details = CreatePreauthenticatedRequestDetails.builder()
                    .name("PAR-" + System.currentTimeMillis())
                    .objectName(objectName)
                    .accessType(CreatePreauthenticatedRequestDetails.AccessType.ObjectRead)
                    .timeExpires(new java.util.Date(System.currentTimeMillis() + validityInSeconds * 1000))
                    .build();

            CreatePreauthenticatedRequestRequest request = CreatePreauthenticatedRequestRequest.builder()
                    .namespaceName(namespaceName)
                    .bucketName(bucketName)
                    .createPreauthenticatedRequestDetails(details)
                    .build();

            CreatePreauthenticatedRequestResponse response = client.createPreauthenticatedRequest(request);

            String baseUrl = client.getEndpoint();
            String parUrl = baseUrl + response.getPreauthenticatedRequest().getAccessUri();
            log.info("生成预签名URL (bucket={}): {}", bucketName, parUrl);
            return parUrl;
        } catch (Exception e) {
            log.error("生成预签名URL失败 (bucket={}): {}", bucketName, e.getMessage(), e);
            return null;
        }
    }

    /**
     * 创建指定名称的存储桶
     * @param tenant 身份验证提供程序
     * @param bucketName 存储桶名称
     * @param publicAccessType 公共访问类型 (NoPublicAccess, ObjectRead, ObjectReadWithoutList)
     * @return 是否创建成功
     */
    public static boolean createNamedBucket(Tenant tenant,
                                            String bucketName,
                                            String publicAccessType) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        String compartmentId = provider.getTenantId();
        try (ObjectStorageClient client = ObjectStorageClient.builder().build(provider)) {
            CreateBucketDetails.PublicAccessType accessType = CreateBucketDetails.PublicAccessType.NoPublicAccess;
            if ("ObjectRead".equalsIgnoreCase(publicAccessType)) {
                accessType = CreateBucketDetails.PublicAccessType.ObjectRead;
            } else if ("ObjectReadWithoutList".equalsIgnoreCase(publicAccessType)) {
                accessType = CreateBucketDetails.PublicAccessType.ObjectReadWithoutList;
            }

            Map<String, String> freeTags = new HashMap<>();
            freeTags.put("accessType",accessType.getValue());
            CreateBucketDetails bucketDetails = CreateBucketDetails.builder()
                    .name(bucketName)
                    .compartmentId(compartmentId)
                    .publicAccessType(accessType)
                    .freeformTags(freeTags)
                    .build();

            CreateBucketRequest request = CreateBucketRequest.builder()
                    .namespaceName(getNamespace(provider))
                    .createBucketDetails(bucketDetails)
                    .build();

            client.createBucket(request);
            log.info("成功创建存储桶: {}", bucketName);
            return true;
        } catch (Exception e) {
            log.error("创建存储桶失败 (bucketName={}): {}", bucketName, e.getMessage(), e);
            return false;
        }
    }

    /**
     * 删除指定存储桶中的对象
     * @param tenant 身份验证提供程序
     * @param namespaceName 命名空间名称
     * @param bucketName 存储桶名称
     * @param objectName 对象名称
     * @return 是否删除成功
     */
    public static boolean deleteNamedObject(Tenant tenant,
                                            String namespaceName,
                                            String bucketName,
                                            String objectName) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        try (ObjectStorageClient client = ObjectStorageClient.builder().build(provider)) {
            DeleteObjectRequest request = DeleteObjectRequest.builder()
                    .namespaceName(namespaceName)
                    .bucketName(bucketName)
                    .objectName(objectName)
                    .build();

            client.deleteObject(request);
            log.info("成功删除对象 {}/{}", bucketName, objectName);
            return true;
        } catch (Exception e) {
            log.error("删除对象失败 (bucket={}, object={}): {}", bucketName, objectName, e.getMessage(), e);
            return false;
        }
    }

    /**
    * @Description: 向存储桶上传JSON字符串
    * @Param: [com.doubledimple.dao.entity.Tenant, java.lang.String, java.lang.String, java.lang.String]
    * @return: boolean
    * @Author: doubleDimple
    * @Date: 4/12/26 4:49 PM
    */
    public static boolean uploadJsonStringForBucketName(Tenant tenant,
                                                        SimpleAuthenticationDetailsProvider provider,
                                           String bucketName,
                                           String objectName,
                                           String jsonString){
        boolean orCreateBucket = getOrCreateDefBucket(tenant,provider, bucketName);
        if (orCreateBucket){
            uploadJsonString(provider, bucketName, objectName, jsonString);
        }
        return true;
    }

    public static boolean uploadJsonString(SimpleAuthenticationDetailsProvider provider,
                                           String bucketName,
                                           String objectName,
                                           String jsonString) {
        try (ObjectStorageClient client = ObjectStorageClient.builder().build(provider)) {
            byte[] contentBytes = jsonString.getBytes("UTF-8");
            final String namespace = getNamespace(provider);
            Map<String, String> metadata = new HashMap<>();

            try (java.io.ByteArrayInputStream contentStream = new java.io.ByteArrayInputStream(contentBytes)) {
                PutObjectRequest request = PutObjectRequest.builder()
                        .namespaceName(namespace)
                        .bucketName(bucketName)
                        .objectName(objectName)
                        .contentType("application/json")
                        .contentLength((long) contentBytes.length)
                        .putObjectBody(contentStream)
                        .opcMeta(metadata)
                        .build();

                client.putObject(request);
                log.debug("成功上传JSON字符串到存储桶 {}/{}: 大小: {} bytes",
                        BUCKET_NAME, objectName, contentBytes.length);
                return true;
            }
        } catch (Exception e) {
            log.error("上传JSON字符串失败: {}", e.getMessage(), e);
            return false;
        }
    }

    /**
     * 上传JSON字符串到存储桶
     * @param tenant 身份验证提供程序
     * @param objectName 对象名称（在存储桶中的路径）
     * @param jsonString 要上传的JSON字符串
     * @return 是否上传成功
     */
    public static boolean uploadJsonString(Tenant tenant,
                                           String bucketName,
                                           String objectName,
                                           String jsonString) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        try (ObjectStorageClient client = ObjectStorageClient.builder().build(provider)) {
            byte[] contentBytes = jsonString.getBytes("UTF-8");
            final String namespace = getNamespace(provider);
            Map<String, String> metadata = new HashMap<>();

            try (java.io.ByteArrayInputStream contentStream = new java.io.ByteArrayInputStream(contentBytes)) {
                PutObjectRequest request = PutObjectRequest.builder()
                        .namespaceName(namespace)
                        .bucketName(bucketName)
                        .objectName(objectName)
                        .contentType("application/json")
                        .contentLength((long) contentBytes.length)
                        .putObjectBody(contentStream)
                        .opcMeta(metadata)
                        .build();

                client.putObject(request);
                log.debug("成功上传JSON字符串到存储桶 {}/{}: 大小: {} bytes",
                        BUCKET_NAME, objectName, contentBytes.length);
                return true;
            }
        } catch (Exception e) {
            log.error("上传JSON字符串失败: {}", e.getMessage(), e);
            return false;
        }
    }

    /**
     * 下载JSON对象并返回字符串
     * @param tenant 身份验证提供程序
     * @param objectName 对象名称
     * @return JSON字符串，如果失败则返回null
     */
    public static String downloadJsonString(Tenant tenant,
                                            String objectName) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        try (ObjectStorageClient client = ObjectStorageClient.builder().build(provider)) {
            GetObjectRequest request = GetObjectRequest.builder()
                    .namespaceName(getNamespace(provider))
                    .bucketName(BUCKET_NAME)
                    .objectName(objectName)
                    .build();

            GetObjectResponse response = client.getObject(request);

            // 读取内容并转换为字符串
            java.io.ByteArrayOutputStream outputStream = new java.io.ByteArrayOutputStream();
            byte[] buffer = new byte[8192];
            int bytesRead;
            while ((bytesRead = response.getInputStream().read(buffer)) != -1) {
                outputStream.write(buffer, 0, bytesRead);
            }

            String jsonContent = outputStream.toString("UTF-8");
            log.debug("成功下载JSON字符串: {}", objectName);
            return jsonContent;
        } catch (Exception e) {
            log.warn("下载JSON字符串失败: {}", e.getMessage());
            return null;
        }
    }

    /**
    * @Description: 创建默认存储桶
    */
    public static boolean getOrCreateBucket(Tenant tenant){
        return getOrCreateBucket(tenant,null,BUCKET_NAME,DEFAULT_ACCESS_TYPE);
    }

    //创建指定名称的存储桶
    public static boolean getOrCreateDefBucket(Tenant tenant,SimpleAuthenticationDetailsProvider provider,String bucketName){
        return getOrCreateBucket(tenant,provider,bucketName,DEFAULT_ACCESS_TYPE);
    }


    /**
     * 检查存储桶是否存在，如果不存在则创建
     * @param tenant 身份验证提供程序
     * @param publicAccessType
     * 公共访问类型
     * (NoPublicAccess, (// 设置为无公共访问)
     * ObjectRead,
     * ObjectReadWithoutList)
     * @return 是否成功（存在或创建成功返回true）
     */
    public static boolean getOrCreateBucket(Tenant tenant,
                                            SimpleAuthenticationDetailsProvider provider,
                                            String bucketName,
                                            String publicAccessType) {
        if (provider == null){
            provider = getProvider(tenant);
        }
        String compartmentId = provider.getTenantId();
        final String namespace = getNamespace(provider);
        try (ObjectStorageClient client = ObjectStorageClient.builder().build(provider)) {
            // 先检查存储桶是否存在
            boolean bucketExists = false;

            try {
                // 通过获取存储桶详情来检查是否存在
                GetBucketRequest getBucketRequest = GetBucketRequest.builder()
                        .namespaceName(namespace)
                        .bucketName(bucketName)
                        .build();

                client.getBucket(getBucketRequest);
                bucketExists = true;
                log.debug("存储桶已存在: {}", BUCKET_NAME);
            } catch (Exception e) {
                // 如果不存在会抛出异常
                log.debug("存储桶不存在: {}, 准备创建", BUCKET_NAME);
                bucketExists = false;
            }

            // 如果存储桶不存在，则创建
            if (!bucketExists) {
                // 设置存储桶的公共访问类型
                CreateBucketDetails.PublicAccessType accessType = CreateBucketDetails.PublicAccessType.NoPublicAccess;
                if ("ObjectRead".equalsIgnoreCase(publicAccessType)) {
                    accessType = CreateBucketDetails.PublicAccessType.ObjectRead;
                } else if ("ObjectReadWithoutList".equalsIgnoreCase(publicAccessType)) {
                    accessType = CreateBucketDetails.PublicAccessType.ObjectReadWithoutList;
                }

                CreateBucketDetails bucketDetails = CreateBucketDetails.builder()
                        .name(BUCKET_NAME)
                        .compartmentId(compartmentId)
                        .publicAccessType(accessType)
                        .build();

                CreateBucketRequest createRequest = CreateBucketRequest.builder()
                        .namespaceName(namespace)
                        .createBucketDetails(bucketDetails)
                        .build();

                try {
                    client.createBucket(createRequest);
                    log.info("成功创建存储桶: {}", BUCKET_NAME);
                    return true;
                } catch (Exception createEx) {
                    log.error("创建存储桶失败: {}", createEx.getMessage(), createEx);
                    return false;
                }
            }

            // 如果存储桶已经存在，直接返回成功
            return true;
        } catch (Exception e) {
            log.error("检查或创建存储桶过程出错: {}", e.getMessage(), e);
            return false;
        }
    }


    private static String getNamespace(AuthenticationDetailsProvider provider) {
        try(ObjectStorageClient client = ObjectStorageClient.builder().build(provider)) {
            // 创建获取命名空间的请求
            GetNamespaceRequest request = GetNamespaceRequest.builder().build();

            // 发送请求并获取响应
            String namespace = client.getNamespace(request).getValue();

            log.debug("成功获取OCI命名空间: {}", namespace);
            return namespace;
        } catch (Exception e) {
            log.error("获取命名空间失败: {}", e.getMessage(), e);
            throw new RuntimeException("无法获取OCI命名空间", e);
        }
    }

    /**
     * 上传文件流到指定存储桶
     *
     * @param tenant      租户
     * @param namespace   命名空间
     * @param bucketName  存储桶名称
     * @param objectName  对象名称（含路径）
     * @param inputStream 文件输入流
     * @param contentType 内容类型
     * @param contentLength 文件大小（字节）
     * @return 是否成功
     */
    public static boolean uploadNamedObject(Tenant tenant,
                                            String namespace,
                                            String bucketName,
                                            String objectName,
                                            InputStream inputStream,
                                            String contentType,
                                            long contentLength) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        try (ObjectStorageClient client = ObjectStorageClient.builder().build(provider)) {
            if (contentType == null || contentType.isEmpty()) {
                contentType = "application/octet-stream";
            }
            PutObjectRequest request = PutObjectRequest.builder()
                    .namespaceName(namespace)
                    .bucketName(bucketName)
                    .objectName(objectName)
                    .contentType(contentType)
                    .contentLength(contentLength)
                    .putObjectBody(inputStream)
                    .build();
            client.putObject(request);
            log.info("上传成功: {}/{}/{}", namespace, bucketName, objectName);
            return true;
        } catch (Exception e) {
            log.error("上传失败 (bucket={}, object={}): {}", bucketName, objectName, e.getMessage(), e);
            return false;
        }
    }

    /**
     * 从指定存储桶下载对象，返回输入流（调用方负责关闭）
     *
     * @param tenant     租户
     * @param namespace  命名空间
     * @param bucketName 存储桶名称
     * @param objectName 对象名称
     * @return GetObjectResponse，通过 getInputStream() 获取内容；失败返回 null
     */
    public static GetObjectResponse downloadNamedObject(Tenant tenant,
                                                        String namespace,
                                                        String bucketName,
                                                        String objectName) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        try {
            ObjectStorageClient client = ObjectStorageClient.builder().build(provider);
            GetObjectRequest request = GetObjectRequest.builder()
                    .namespaceName(namespace)
                    .bucketName(bucketName)
                    .objectName(objectName)
                    .build();
            return client.getObject(request);
        } catch (Exception e) {
            log.error("下载失败 (bucket={}, object={}): {}", bucketName, objectName, e.getMessage(), e);
            return null;
        }
    }

    // ─────────────────────────────────────────────────────────────
    //  分片上传 (Multipart Upload)
    // ─────────────────────────────────────────────────────────────

    /**
     * 初始化分片上传，返回 uploadId
     */
    public static String initiateMultipartUpload(Tenant tenant,
                                                  String namespace,
                                                  String bucketName,
                                                  String objectName,
                                                  String contentType) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        try (ObjectStorageClient client = ObjectStorageClient.builder().build(provider)) {
            if (contentType == null || contentType.isEmpty()) {
                contentType = "application/octet-stream";
            }
            CreateMultipartUploadDetails details = CreateMultipartUploadDetails.builder()
                    .object(objectName)
                    .contentType(contentType)
                    .build();
            CreateMultipartUploadRequest request = CreateMultipartUploadRequest.builder()
                    .namespaceName(namespace)
                    .bucketName(bucketName)
                    .createMultipartUploadDetails(details)
                    .build();
            CreateMultipartUploadResponse response = client.createMultipartUpload(request);
            String uploadId = response.getMultipartUpload().getUploadId();
            log.info("初始化分片上传成功 uploadId={} bucket={} object={}", uploadId, bucketName, objectName);
            return uploadId;
        } catch (Exception e) {
            log.error("初始化分片上传失败 (bucket={}, object={}): {}", bucketName, objectName, e.getMessage(), e);
            return null;
        }
    }

    /**
     * 上传单个分片，返回 ETag
     */
    public static String uploadPart(Tenant tenant,
                                     String namespace,
                                     String bucketName,
                                     String objectName,
                                     String uploadId,
                                     int partNumber,
                                     InputStream partStream,
                                     long partSize) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        try (ObjectStorageClient client = ObjectStorageClient.builder().build(provider)) {
            UploadPartRequest request = UploadPartRequest.builder()
                    .namespaceName(namespace)
                    .bucketName(bucketName)
                    .objectName(objectName)
                    .uploadId(uploadId)
                    .uploadPartNum(partNumber)
                    .contentLength(partSize)
                    .uploadPartBody(partStream)
                    .build();
            UploadPartResponse response = client.uploadPart(request);
            String etag = response.getETag();
            log.debug("上传分片成功 part={} etag={}", partNumber, etag);
            return etag;
        } catch (Exception e) {
            log.error("上传分片失败 (uploadId={}, part={}): {}", uploadId, partNumber, e.getMessage(), e);
            return null;
        }
    }

    /**
     * 提交分片上传
     */
    public static boolean commitMultipartUpload(Tenant tenant,
                                                 String namespace,
                                                 String bucketName,
                                                 String objectName,
                                                 String uploadId,
                                                 List<CommitMultipartUploadPartDetails> parts) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        try (ObjectStorageClient client = ObjectStorageClient.builder().build(provider)) {
            CommitMultipartUploadDetails details = CommitMultipartUploadDetails.builder()
                    .partsToCommit(parts)
                    .build();
            CommitMultipartUploadRequest request = CommitMultipartUploadRequest.builder()
                    .namespaceName(namespace)
                    .bucketName(bucketName)
                    .objectName(objectName)
                    .uploadId(uploadId)
                    .commitMultipartUploadDetails(details)
                    .build();
            client.commitMultipartUpload(request);
            log.info("提交分片上传成功 uploadId={} object={}", uploadId, objectName);
            return true;
        } catch (Exception e) {
            log.error("提交分片上传失败 (uploadId={}): {}", uploadId, e.getMessage(), e);
            return false;
        }
    }

    /**
     * 取消分片上传（清理残留分片）
     */
    public static boolean abortMultipartUpload(Tenant tenant,
                                                String namespace,
                                                String bucketName,
                                                String objectName,
                                                String uploadId) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        try (ObjectStorageClient client = ObjectStorageClient.builder().build(provider)) {
            AbortMultipartUploadRequest request = AbortMultipartUploadRequest.builder()
                    .namespaceName(namespace)
                    .bucketName(bucketName)
                    .objectName(objectName)
                    .uploadId(uploadId)
                    .build();
            client.abortMultipartUpload(request);
            log.info("已取消分片上传 uploadId={}", uploadId);
            return true;
        } catch (Exception e) {
            log.error("取消分片上传失败 (uploadId={}): {}", uploadId, e.getMessage(), e);
            return false;
        }
    }

    /**
     * 分页查询存储桶列表
     */
    public static Map<String, Object> listBucketsPaginated(Tenant tenant, int limit, String pageToken) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        String compartmentId = provider.getTenantId();
        try (ObjectStorageClient client = ObjectStorageClient.builder().build(provider)) {
            final String namespace = getNamespace(provider);

            ListBucketsRequest.Builder requestBuilder = ListBucketsRequest.builder()
                    .namespaceName(namespace)
                    .compartmentId(compartmentId)
                    .limit(limit)
                    .fields(Collections.singletonList(ListBucketsRequest.Fields.Tags));

            // 如果传入了翻页令牌，设置page
            if (StringUtils.hasText(pageToken)) {
                requestBuilder.page(pageToken);
            }

            ListBucketsResponse response = client.listBuckets(requestBuilder.build());

            Map<String, Object> result = new HashMap<>();
            result.put("items", response.getItems());
            result.put("nextPage", response.getOpcNextPage());
            return result;
        } catch (Exception e) {
            log.error("分页获取存储桶列表失败: {}", e.getMessage(), e);
            throw new RuntimeException("分页获取存储桶列表失败", e);
        }
    }

    /**
     * 删除存储桶
     */
    public static boolean deleteNamedBucket(Tenant tenant, String namespace, String bucketName) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        try (ObjectStorageClient client = ObjectStorageClient.builder().build(provider)) {
            DeleteBucketRequest request = DeleteBucketRequest.builder()
                    .namespaceName(namespace)
                    .bucketName(bucketName)
                    .build();

            client.deleteBucket(request);
            log.info("成功删除存储桶: {}", bucketName);
            return true;
        } catch (Exception e) {
            log.error("删除存储桶失败 (bucketName={}): {}", bucketName, e.getMessage(), e);
            return false;
        }
    }

    /**
     * 分页查询对象列表
     */
    public static Map<String, Object> listObjectsPaginated(Tenant tenant, String namespace, String bucketName,
                                                           String prefix, int limit, String startToken) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        try (ObjectStorageClient client = ObjectStorageClient.builder().build(provider)) {

            ListObjectsRequest.Builder requestBuilder = ListObjectsRequest.builder()
                    .namespaceName(namespace)
                    .bucketName(bucketName)
                    .limit(limit);

            if (StringUtils.hasText(prefix)) {
                requestBuilder.prefix(prefix);
            }
            if (StringUtils.hasText(startToken)) {
                requestBuilder.start(startToken);
            }

            ListObjectsResponse response = client.listObjects(requestBuilder.build());

            Map<String, Object> result = new HashMap<>();
            result.put("items", response.getListObjects().getObjects());
            result.put("nextStartWith", response.getListObjects().getNextStartWith());

            return result;
        } catch (Exception e) {
            log.error("分页获取对象列表失败, bucket={}: {}", bucketName, e.getMessage(), e);
            throw new RuntimeException("分页获取对象列表失败", e);
        }
    }
}
