package com.doubledimple.ociserver.third.openApi.controller;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ociai.chat.ChatAiService;
import com.doubledimple.ocicommon.param.OpenAIChatRequest;
import com.doubledimple.ocicommon.param.OpenAIChatResponse;
import com.doubledimple.ociserver.pojo.request.PresignedUrlRequest;
import com.doubledimple.ociserver.pojo.response.BucketVO;
import com.doubledimple.ociserver.pojo.response.ObjectVO;
import com.doubledimple.ociserver.pojo.response.PresignedUrlVO;
import com.doubledimple.ociserver.service.TenantService;
import com.doubledimple.ociserver.third.openApi.annotation.RequireApiToken;
import com.doubledimple.ociserver.third.openApi.request.AiChatRequest;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.utils.oracle.OciObjectStorageUtil;
import com.oracle.bmc.objectstorage.model.BucketSummary;
import com.oracle.bmc.objectstorage.model.ObjectSummary;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import javax.annotation.Resource;
import javax.servlet.http.HttpServletResponse;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/oci-start/open-api/v1")
@Tag(name = "OCI-START OPEN-API", description = "开放API接口")
@Slf4j
public class OpenApiController {

    @Resource
    private ChatAiService chatAiService;

    @Resource
    private TenantService tenantService;
    

    /**
    * @Description: ai聊天
    * @Param:
    * @return:
    * @Author: doubleDimple
    * @Date: 9/12/25 10:06 AM
    */
    @PostMapping("/chat")
    @Operation(summary = "ai聊天", description = "使用ai进行聊天")
    @RequireApiToken
    public ApiResponse chat(@RequestBody AiChatRequest aiChatRequest) {
        if (StringUtils.isBlank(aiChatRequest.getUserId())){
            return ApiResponse.error("用户ID不能为空");
        }
        if (StringUtils.isBlank(aiChatRequest.getMessage())){
            return ApiResponse.error("输入消息不能为空");
        }
        ApiResponse result = chatAiService.chat(aiChatRequest.getUserId(), aiChatRequest.getMessage(),null)
                .thenApply(ApiResponse::success).join();
        log.info("ai聊天结果: {}", result);
        return result;
    }

    @PostMapping(value = "/chat/completions")
    @Operation(summary = "OpenAI兼容聊天接口", description = "同时兼容 stream=true 和 stream=false")
    @RequireApiToken
    public Object chatCompletions(
            @RequestBody OpenAIChatRequest request,
            @RequestHeader(value = "X-User-Id", defaultValue = "admin") String userId,
            HttpServletResponse httpResponse) {

        if (Boolean.TRUE.equals(request.getStream())) {
            SseEmitter emitter = new SseEmitter(0L);
            chatAiService.handleOpenAiStreamBridgeSse(request, userId, emitter);
            return emitter;
        }

        return chatAiService.chatCompletions(request, userId,httpResponse);
    }

    /**
     * new-api标准的模型列表接口
     */
    @GetMapping("/models")
    @Operation(summary = "获取模型列表", description = "返回符合OpenAI标准的模型列表，供new-api使用")
    @RequireApiToken
    public Map<String, Object> models() {
        return chatAiService.enableModels();
    }

    // ─────────────────────────────────────────
    //  OCI 对象存储 Open API
    // ─────────────────────────────────────────

    /**
     * 获取指定租户的存储桶列表
     */
    @GetMapping("/storage/buckets")
    @Operation(summary = "获取存储桶列表", description = "获取指定租户下的所有OCI存储桶")
    @RequireApiToken
    public ApiResponse listBuckets(@RequestParam Long tenantId) {
        try {
            Tenant tenant = tenantService.getById(tenantId);
            if (tenant == null) {
                return ApiResponse.error("租户不存在");
            }
            List<BucketSummary> buckets = OciObjectStorageUtil.listBuckets(tenant);
            List<BucketVO> result = buckets.stream().map(b -> BucketVO.builder()
                    .name(b.getName())
                    .namespace(b.getNamespace())
                    .timeCreated(b.getTimeCreated() != null ? b.getTimeCreated().toString() : null)
                    .publicAccess(b.getFreeformTags() != null ? b.getFreeformTags().getOrDefault("accessType", "NoPublicAccess") : "NoPublicAccess")
                    .build()
            ).collect(Collectors.toList());
            return ApiResponse.success(result);
        } catch (Exception e) {
            log.error("[OpenAPI] 获取存储桶列表失败, tenantId={}", tenantId, e);
            return ApiResponse.error("获取存储桶列表失败: " + e.getMessage());
        }
    }

    /**
     * 获取存储桶中的对象列表
     */
    @GetMapping("/storage/objects")
    @Operation(summary = "获取对象列表", description = "获取指定存储桶下的对象列表")
    @RequireApiToken
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
            log.error("[OpenAPI] 获取对象列表失败, tenantId={}, bucket={}", tenantId, bucketName, e);
            return ApiResponse.error("获取对象列表失败: " + e.getMessage());
        }
    }

    /**
     * 生成对象预签名URL
     */
    @PostMapping("/storage/object/presigned")
    @Operation(summary = "生成预签名URL", description = "生成OCI对象存储的预签名访问URL")
    @RequireApiToken
    public ApiResponse generatePresignedUrl(@RequestBody PresignedUrlRequest req) {
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
            log.error("[OpenAPI] 生成预签名URL失败", e);
            return ApiResponse.error("生成预签名URL失败: " + e.getMessage());
        }
    }
}