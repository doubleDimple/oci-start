package com.doubledimple.ociserver.controller;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.pojo.request.AbortMultipartUploadRequest;
import com.doubledimple.ociserver.pojo.request.CommitMultipartUploadRequest;
import com.doubledimple.ociserver.pojo.request.CreateBucketRequest;
import com.doubledimple.ociserver.pojo.request.DeleteBucketRequest;
import com.doubledimple.ociserver.pojo.request.DeleteObjectRequest;
import com.doubledimple.ociserver.pojo.request.InitiateMultipartUploadRequest;
import com.doubledimple.ociserver.pojo.request.PresignedUrlRequest;
import com.doubledimple.ociserver.pojo.response.BucketVO;
import com.doubledimple.ociserver.pojo.response.InitiateMultipartUploadVO;
import com.doubledimple.ociserver.pojo.response.NamespaceVO;
import com.doubledimple.ociserver.pojo.response.ObjectVO;
import com.doubledimple.ociserver.pojo.response.PresignedUrlVO;
import com.doubledimple.ociserver.pojo.response.MultipartUploadRecordVO;
import com.doubledimple.ociserver.pojo.response.UploadPartVO;
import com.doubledimple.ociserver.service.OciMultipartUploadService;
import com.doubledimple.ociserver.service.TenantService;
import com.doubledimple.ociserver.utils.oracle.OciObjectStorageUtil;
import com.oracle.bmc.objectstorage.model.BucketSummary;
import com.oracle.bmc.objectstorage.model.CommitMultipartUploadPartDetails;
import com.oracle.bmc.objectstorage.model.ObjectSummary;
import com.oracle.bmc.objectstorage.responses.GetObjectResponse;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import javax.annotation.Resource;
import javax.servlet.http.HttpServletResponse;
import javax.validation.Valid;
import java.io.InputStream;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * OCI对象存储管理控制器
 *
 * @author doubleDimple
 */
@Controller
@RequestMapping("/oci/storage")
@Slf4j
public class OciObjectStorageController extends BaseController {

    @Resource
    TenantService tenantService;

    @Resource
    OciMultipartUploadService multipartUploadService;

    /**
     * 对象存储管理页面
     */
    @GetMapping("/page")
    public String page(Model model) {
        model.addAttribute("activePage", "oci-object-storage");
        return "oci_object_storage";
    }

    /**
     * 获取指定租户的存储桶列表
     */
    @GetMapping("/buckets")
    @ResponseBody
    public ApiResponse listBuckets(
            @RequestParam Long tenantId,
            @RequestParam(required = false, defaultValue = "100") Integer limit,
            @RequestParam(required = false) String pageToken) {
        try {
            Tenant tenant = tenantService.getById(tenantId);
            if (tenant == null) {
                return ApiResponse.error("租户不存在");
            }

            // 返回包含数据列表和下一页Token的Map
            Map<String, Object> pageData = OciObjectStorageUtil.listBucketsPaginated(tenant, limit, pageToken);
            List<BucketSummary> buckets = (List<BucketSummary>) pageData.get("items");

            List<BucketVO> result = buckets.stream().map(b -> BucketVO.builder()
                    .name(b.getName())
                    .namespace(b.getNamespace())
                    .timeCreated(b.getTimeCreated() != null ? b.getTimeCreated().toString() : null)
                    .publicAccess(b.getFreeformTags() != null ? b.getFreeformTags().getOrDefault("accessType", "NoPublicAccess") : "NoPublicAccess")
                    .build()
            ).collect(Collectors.toList());

            // 重新包装分页结果
            Map<String, Object> responseData = new HashMap<>();
            responseData.put("items", result);
            responseData.put("nextPage", pageData.get("nextPage")); // 如果没有下一页，这里会是null

            return ApiResponse.success(responseData);
        } catch (Exception e) {
            log.error("获取存储桶列表失败, tenantId={}", tenantId, e);
            return ApiResponse.error("获取存储桶列表失败: " + e.getMessage());
        }
    }

    /**
     * 创建存储桶
     */
    @PostMapping("/bucket/create")
    @ResponseBody
    public ApiResponse createBucket(@RequestBody @Valid CreateBucketRequest req) {
        try {
            Tenant tenant = tenantService.getById(req.getTenantId());
            if (tenant == null) {
                return ApiResponse.error("租户不存在");
            }
            boolean success = OciObjectStorageUtil.createNamedBucket(
                    tenant,req.getBucketName().trim(), req.getPublicAccessType());
            return success ? ApiResponse.success("存储桶创建成功") : ApiResponse.error("存储桶创建失败");
        } catch (Exception e) {
            log.error("创建存储桶失败", e);
            return ApiResponse.error("创建存储桶失败: " + e.getMessage());
        }
    }

    /**
     * 获取存储桶中的对象列表
     */
    /*@GetMapping("/objects")
    @ResponseBody
    public ApiResponse listObjects(
            @RequestParam Long tenantId,
            @RequestParam String namespace,
            @RequestParam String bucketName,
            @RequestParam(required = false, defaultValue = "") String prefix) {
        try {
            Tenant tenant = tenantService.getById(tenantId);
            if (tenant == null) {
                return ApiResponse.error("租户不存在");
            }
            List<ObjectSummary> objects = OciObjectStorageUtil.listObjects(tenant, namespace, bucketName, prefix);
            List<ObjectVO> result = objects.stream().map(o -> ObjectVO.builder()
                    .name(o.getName())
                    .size(o.getSize())
                    .timeModified(o.getTimeModified() != null ? o.getTimeModified().toString() : null)
                    .build()
            ).collect(Collectors.toList());
            return ApiResponse.success(result);
        } catch (Exception e) {
            log.error("获取对象列表失败, tenantId={}, bucket={}", tenantId, bucketName, e);
            return ApiResponse.error("获取对象列表失败: " + e.getMessage());
        }
    }*/

    /**
     * 删除对象
     */
    @PostMapping("/object/delete")
    @ResponseBody
    public ApiResponse deleteObject(@RequestBody @Valid DeleteObjectRequest req) {
        try {
            Tenant tenant = tenantService.getById(req.getTenantId());
            if (tenant == null) {
                return ApiResponse.error("租户不存在");
            }
            boolean success = OciObjectStorageUtil.deleteNamedObject(
                    tenant, req.getNamespace(), req.getBucketName(), req.getObjectName());
            return success ? ApiResponse.success("对象删除成功") : ApiResponse.error("对象删除失败");
        } catch (Exception e) {
            log.error("删除对象失败", e);
            return ApiResponse.error("删除对象失败: " + e.getMessage());
        }
    }

    /**
     * 生成对象预签名URL
     */
    @PostMapping("/object/presigned")
    @ResponseBody
    public ApiResponse generatePresignedUrl(@RequestBody @Valid PresignedUrlRequest req) {
        try {
            Tenant tenant = tenantService.getById(req.getTenantId());
            if (tenant == null) {
                return ApiResponse.error("租户不存在");
            }
            String url = OciObjectStorageUtil.generatePresignedUrlForBucket(
                    tenant, req.getNamespace(), req.getBucketName(), req.getObjectName(), req.getValiditySeconds());
            if (url != null) {
                return ApiResponse.success(PresignedUrlVO.builder().url(url).build());
            } else {
                return ApiResponse.error("生成预签名URL失败");
            }
        } catch (Exception e) {
            log.error("生成预签名URL失败", e);
            return ApiResponse.error("生成预签名URL失败: " + e.getMessage());
        }
    }

    /**
     * 上传文件到存储桶
     */
    @PostMapping("/object/upload")
    @ResponseBody
    public ApiResponse uploadObject(
            @RequestParam Long tenantId,
            @RequestParam String namespace,
            @RequestParam String bucketName,
            @RequestParam(required = false) String objectName,
            @RequestParam("file") MultipartFile file) {
        try {
            if (file.isEmpty()) {
                return ApiResponse.error("文件不能为空");
            }
            Tenant tenant = tenantService.getById(tenantId);
            if (tenant == null) {
                return ApiResponse.error("租户不存在");
            }
            String finalObjectName = StringUtils.hasText(objectName)
                    ? objectName
                    : file.getOriginalFilename();
            String contentType = file.getContentType();
            try (InputStream is = file.getInputStream()) {
                boolean success = OciObjectStorageUtil.uploadNamedObject(
                        tenant, namespace, bucketName, finalObjectName, is, contentType, file.getSize());
                return success ? ApiResponse.success("上传成功") : ApiResponse.error("上传失败");
            }
        } catch (Exception e) {
            log.error("上传文件失败, bucket={}", bucketName, e);
            return ApiResponse.error("上传失败: " + e.getMessage());
        }
    }

    /**
     * 下载对象（浏览器触发下载）
     */
    @GetMapping("/object/download")
    public void downloadObject(
            @RequestParam Long tenantId,
            @RequestParam String namespace,
            @RequestParam String bucketName,
            @RequestParam String objectName,
            HttpServletResponse response) {
        try {
            Tenant tenant = tenantService.getById(tenantId);
            if (tenant == null) {
                response.sendError(HttpServletResponse.SC_BAD_REQUEST, "租户不存在");
                return;
            }
            GetObjectResponse ociResp = OciObjectStorageUtil.downloadNamedObject(tenant, namespace, bucketName, objectName);
            if (ociResp == null) {
                response.sendError(HttpServletResponse.SC_NOT_FOUND, "对象不存在或下载失败");
                return;
            }
            String fileName = objectName.contains("/")
                    ? objectName.substring(objectName.lastIndexOf('/') + 1)
                    : objectName;
            String encodedName = URLEncoder.encode(fileName, StandardCharsets.UTF_8.name()).replace("+", "%20");
            String contentType = ociResp.getContentType() != null ? ociResp.getContentType() : "application/octet-stream";
            response.setContentType(contentType);
            response.setHeader(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename*=UTF-8''" + encodedName);
            if (ociResp.getContentLength() != null) {
                response.setHeader(HttpHeaders.CONTENT_LENGTH, String.valueOf(ociResp.getContentLength()));
            }
            try (InputStream is = ociResp.getInputStream()) {
                byte[] buf = new byte[8192];
                int len;
                while ((len = is.read(buf)) != -1) {
                    response.getOutputStream().write(buf, 0, len);
                }
            }
        } catch (Exception e) {
            log.error("下载对象失败, bucket={}, object={}", bucketName, objectName, e);
        }
    }

    /**
     * 预览对象（图片/文本/JSON 等可预览类型内联返回，其他触发下载）
     */
    @GetMapping("/object/preview")
    public void previewObject(
            @RequestParam Long tenantId,
            @RequestParam String namespace,
            @RequestParam String bucketName,
            @RequestParam String objectName,
            HttpServletResponse response) {
        try {
            Tenant tenant = tenantService.getById(tenantId);
            if (tenant == null) {
                response.sendError(HttpServletResponse.SC_BAD_REQUEST, "租户不存在");
                return;
            }
            GetObjectResponse ociResp = OciObjectStorageUtil.downloadNamedObject(tenant, namespace, bucketName, objectName);
            if (ociResp == null) {
                response.sendError(HttpServletResponse.SC_NOT_FOUND, "对象不存在");
                return;
            }
            String contentType = resolveContentType(objectName, ociResp.getContentType());
            response.setContentType(contentType);
            // 可内联预览的类型设为 inline，其余触发下载
            if (isInlinePreviewable(contentType)) {
                response.setHeader(HttpHeaders.CONTENT_DISPOSITION, "inline");
            } else {
                String fileName = objectName.contains("/")
                        ? objectName.substring(objectName.lastIndexOf('/') + 1)
                        : objectName;
                String encodedName = URLEncoder.encode(fileName, StandardCharsets.UTF_8.name()).replace("+", "%20");
                response.setHeader(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename*=UTF-8''" + encodedName);
            }
            if (ociResp.getContentLength() != null) {
                response.setHeader(HttpHeaders.CONTENT_LENGTH, String.valueOf(ociResp.getContentLength()));
            }
            try (InputStream is = ociResp.getInputStream()) {
                byte[] buf = new byte[8192];
                int len;
                while ((len = is.read(buf)) != -1) {
                    response.getOutputStream().write(buf, 0, len);
                }
            }
        } catch (Exception e) {
            log.error("预览对象失败, bucket={}, object={}", bucketName, objectName, e);
        }
    }

    private String resolveContentType(String objectName, String ociContentType) {
        if (StringUtils.hasText(ociContentType) && !"application/octet-stream".equals(ociContentType)) {
            return ociContentType;
        }
        String lower = objectName.toLowerCase();
        if (lower.endsWith(".png"))  return MediaType.IMAGE_PNG_VALUE;
        if (lower.endsWith(".jpg") || lower.endsWith(".jpeg")) return MediaType.IMAGE_JPEG_VALUE;
        if (lower.endsWith(".gif"))  return "image/gif";
        if (lower.endsWith(".webp")) return "image/webp";
        if (lower.endsWith(".svg"))  return "image/svg+xml";
        if (lower.endsWith(".pdf"))  return MediaType.APPLICATION_PDF_VALUE;
        if (lower.endsWith(".json")) return MediaType.APPLICATION_JSON_VALUE;
        if (lower.endsWith(".txt") || lower.endsWith(".log") || lower.endsWith(".md"))
            return "text/plain;charset=UTF-8";
        if (lower.endsWith(".html") || lower.endsWith(".htm")) return MediaType.TEXT_HTML_VALUE;
        if (lower.endsWith(".xml"))  return MediaType.APPLICATION_XML_VALUE;
        return MediaType.APPLICATION_OCTET_STREAM_VALUE;
    }

    private boolean isInlinePreviewable(String contentType) {
        if (!StringUtils.hasText(contentType)) return false;
        String t = contentType.toLowerCase();
        return t.startsWith("image/") || t.startsWith("text/")
                || t.contains("pdf") || t.contains("json") || t.contains("xml");
    }

    // ─────────────────────────────────────────
    //  分片上传 (Multipart Upload)
    // ─────────────────────────────────────────

    /**
     * 初始化分片上传，返回 uploadId，并写入上传记录表。
     * 若同一租户+桶+文件名已有进行中的记录，先 abort 旧的再新建，确保表里始终只有一条 uploading 记录。
     */
    @PostMapping("/object/multipart/initiate")
    @ResponseBody
    public ApiResponse initiateMultipartUpload(@RequestBody @Valid InitiateMultipartUploadRequest req) {
        try {
            Tenant tenant = tenantService.getById(req.getTenantId());
            if (tenant == null) {
                return ApiResponse.error("租户不存在");
            }

            // 去重：abort 掉所有同文件的旧 uploading 记录
            List<com.doubledimple.dao.entity.OciMultipartUploadRecord> oldRecords =
                    multipartUploadService.findActiveUploads(req.getTenantId(), req.getBucketName(), req.getObjectName());
            for (com.doubledimple.dao.entity.OciMultipartUploadRecord old : oldRecords) {
                OciObjectStorageUtil.abortMultipartUpload(tenant, old.getNamespace(),
                        old.getBucketName(), old.getObjectName(), old.getUploadId());
                multipartUploadService.markAborted(old.getUploadId());
                log.info("已清理旧分片上传记录 uploadId={} object={}", old.getUploadId(), old.getObjectName());
            }

            String uploadId = OciObjectStorageUtil.initiateMultipartUpload(
                    tenant, req.getNamespace(), req.getBucketName(), req.getObjectName(), req.getContentType());
            if (uploadId == null) {
                return ApiResponse.error("初始化分片上传失败");
            }
            int totalParts = (req.getTotalSize() != null && req.getChunkSize() != null && req.getChunkSize() > 0)
                    ? (int) Math.ceil((double) req.getTotalSize() / req.getChunkSize()) : 0;
            multipartUploadService.create(
                    req.getTenantId(), tenant.getTenantId(), req.getNamespace(), req.getBucketName(),
                    req.getObjectName(), uploadId,
                    req.getTotalSize(), req.getChunkSize(), totalParts);
            return ApiResponse.success(InitiateMultipartUploadVO.builder()
                    .uploadId(uploadId)
                    .objectName(req.getObjectName())
                    .namespace(req.getNamespace())
                    .bucketName(req.getBucketName())
                    .build());
        } catch (Exception e) {
            log.error("初始化分片上传失败", e);
            return ApiResponse.error("初始化分片上传失败: " + e.getMessage());
        }
    }

    /**
     * 上传单个分片，成功后更新已完成分片列表
     */
    @PostMapping("/object/multipart/part")
    @ResponseBody
    public ApiResponse uploadPart(
            @RequestParam Long tenantId,
            @RequestParam String namespace,
            @RequestParam String bucketName,
            @RequestParam String objectName,
            @RequestParam String uploadId,
            @RequestParam int partNumber,
            @RequestParam("chunk") MultipartFile chunk) {
        try {
            if (chunk.isEmpty()) {
                return ApiResponse.error("分片数据为空");
            }
            Tenant tenant = tenantService.getById(tenantId);
            if (tenant == null) {
                return ApiResponse.error("租户不存在");
            }
            try (InputStream is = chunk.getInputStream()) {
                String etag = OciObjectStorageUtil.uploadPart(
                        tenant, namespace, bucketName, objectName, uploadId, partNumber, is, chunk.getSize());
                if (etag == null) {
                    return ApiResponse.error("分片上传失败");
                }
                multipartUploadService.appendCompletedPart(uploadId, partNumber, etag);
                return ApiResponse.success(UploadPartVO.builder().partNum(partNumber).etag(etag).build());
            }
        } catch (Exception e) {
            log.error("分片上传失败 part={}", partNumber, e);
            return ApiResponse.error("分片上传失败: " + e.getMessage());
        }
    }

    /**
     * 提交分片上传，标记记录为 completed
     */
    @PostMapping("/object/multipart/commit")
    @ResponseBody
    public ApiResponse commitMultipartUpload(@RequestBody @Valid CommitMultipartUploadRequest req) {
        try {
            Tenant tenant = tenantService.getById(req.getTenantId());
            if (tenant == null) {
                return ApiResponse.error("租户不存在");
            }
            List<CommitMultipartUploadPartDetails> parts = req.getParts().stream()
                    .map(p -> CommitMultipartUploadPartDetails.builder()
                            .partNum(p.getPartNum())
                            .etag(p.getEtag())
                            .build())
                    .collect(Collectors.toList());
            boolean success = OciObjectStorageUtil.commitMultipartUpload(
                    tenant, req.getNamespace(), req.getBucketName(), req.getObjectName(), req.getUploadId(), parts);
            if (success) {
                multipartUploadService.markCompleted(req.getUploadId());
                return ApiResponse.success("上传完成");
            }
            return ApiResponse.error("提交分片上传失败");
        } catch (Exception e) {
            log.error("提交分片上传失败", e);
            return ApiResponse.error("提交分片上传失败: " + e.getMessage());
        }
    }

    /**
     * 取消分片上传，标记记录为 aborted
     */
    @PostMapping("/object/multipart/abort")
    @ResponseBody
    public ApiResponse abortMultipartUpload(@RequestBody @Valid AbortMultipartUploadRequest req) {
        try {
            Tenant tenant = tenantService.getById(req.getTenantId());
            if (tenant == null) {
                return ApiResponse.error("租户不存在");
            }
            boolean success = OciObjectStorageUtil.abortMultipartUpload(
                    tenant, req.getNamespace(), req.getBucketName(), req.getObjectName(), req.getUploadId());
            if (success) {
                multipartUploadService.markAborted(req.getUploadId());
                return ApiResponse.success("已取消上传");
            }
            return ApiResponse.error("取消失败");
        } catch (Exception e) {
            log.error("取消分片上传失败", e);
            return ApiResponse.error("取消失败: " + e.getMessage());
        }
    }

    /**
     * 查询当前桶下可断点续传的上传记录
     */
    @GetMapping("/object/multipart/resumeable")
    @ResponseBody
    public ApiResponse listResumeableUploads(@RequestParam Long tenantId,
                                              @RequestParam String bucketName) {
        try {
            List<MultipartUploadRecordVO> list =
                    multipartUploadService.listResumeableUploads(tenantId, bucketName);
            return ApiResponse.success(list);
        } catch (Exception e) {
            log.error("查询可续传记录失败", e);
            return ApiResponse.error("查询失败: " + e.getMessage());
        }
    }

    /**
     * 获取命名空间
     */
    @GetMapping("/namespace")
    @ResponseBody
    public ApiResponse getNamespace(@RequestParam Long tenantId) {
        try {
            Tenant tenant = tenantService.getById(tenantId);
            if (tenant == null) {
                return ApiResponse.error("租户不存在");
            }
            String namespace = OciObjectStorageUtil.getNamespace(tenant);
            if (namespace != null) {
                return ApiResponse.success(NamespaceVO.builder().namespace(namespace).build());
            } else {
                return ApiResponse.error("获取命名空间失败");
            }
        } catch (Exception e) {
            log.error("获取命名空间失败, tenantId={}", tenantId, e);
            return ApiResponse.error("获取命名空间失败: " + e.getMessage());
        }
    }

    /**
     * 删除存储桶
     */
    @PostMapping("/bucket/delete")
    @ResponseBody
    public ApiResponse deleteBucket(@RequestBody @Valid DeleteBucketRequest req) {
        try {
            Tenant tenant = tenantService.getById(req.getTenantId());
            if (tenant == null) {
                return ApiResponse.error("租户不存在");
            }
            boolean success = OciObjectStorageUtil.deleteNamedBucket(
                    tenant, req.getNamespace(), req.getBucketName());
            return success ? ApiResponse.success("存储桶删除成功") : ApiResponse.error("存储桶删除失败");
        } catch (Exception e) {
            log.error("删除存储桶失败", e);
            return ApiResponse.error("删除存储桶失败: " + e.getMessage());
        }
    }

    /**
     * 获取存储桶中的对象列表 (支持分页)
     */
    @GetMapping("/objects")
    @ResponseBody
    public ApiResponse listObjects(
            @RequestParam Long tenantId,
            @RequestParam String namespace,
            @RequestParam String bucketName,
            @RequestParam(required = false, defaultValue = "") String prefix,
            @RequestParam(required = false, defaultValue = "100") Integer limit,
            @RequestParam(required = false) String startToken) {
        try {
            Tenant tenant = tenantService.getById(tenantId);
            if (tenant == null) {
                return ApiResponse.error("租户不存在");
            }

            Map<String, Object> pageData = OciObjectStorageUtil.listObjectsPaginated(
                    tenant, namespace, bucketName, prefix, limit, startToken);
            List<ObjectSummary> objects = (List<ObjectSummary>) pageData.get("items");

            List<ObjectVO> result = objects.stream().map(o -> ObjectVO.builder()
                    .name(o.getName())
                    .size(o.getSize())
                    .timeModified(o.getTimeModified() != null ? o.getTimeModified().toString() : null)
                    .build()
            ).collect(Collectors.toList());

            Map<String, Object> responseData = new HashMap<>();
            responseData.put("items", result);
            responseData.put("nextStartWith", pageData.get("nextStartWith")); // 用于前端请求下一页的游标

            return ApiResponse.success(responseData);
        } catch (Exception e) {
            log.error("获取对象列表失败, tenantId={}, bucket={}", tenantId, bucketName, e);
            return ApiResponse.error("获取对象列表失败: " + e.getMessage());
        }
    }
}
