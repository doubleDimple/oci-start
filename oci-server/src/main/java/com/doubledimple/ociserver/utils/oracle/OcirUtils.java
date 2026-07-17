package com.doubledimple.ociserver.utils.oracle;

import com.doubledimple.dao.entity.Tenant;
import com.oracle.bmc.artifacts.ArtifactsClient;
import com.oracle.bmc.artifacts.model.ContainerImageSummary;
import com.oracle.bmc.artifacts.model.ContainerRepository;
import com.oracle.bmc.artifacts.model.ContainerRepositorySummary;
import com.oracle.bmc.artifacts.requests.DeleteContainerImageRequest;
import com.oracle.bmc.artifacts.requests.DeleteContainerRepositoryRequest;
import com.oracle.bmc.artifacts.requests.ListContainerImagesRequest;
import com.oracle.bmc.artifacts.requests.ListContainerRepositoriesRequest;
import com.oracle.bmc.artifacts.responses.ListContainerImagesResponse;
import com.oracle.bmc.artifacts.responses.ListContainerRepositoriesResponse;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.model.BmcException;
import lombok.extern.slf4j.Slf4j;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.stream.Collectors;
import com.doubledimple.ociserver.config.ProxyContext;

/**
 * OCI 容器镜像仓库 (OCIR) 管理工具类
 * 依赖 ArtifactsClient
 *
 * @author doubleDimple
 * @date 2026:04:02
 */
@Slf4j
public class OcirUtils {

    /**
     * @Description: 获取指定租户(Compartment)下的所有容器镜像仓库
     * @Param: [tenant, compartmentId]
     * @return: java.util.List<com.oracle.bmc.artifacts.model.ContainerRepositorySummary>
     */
    public static List<ContainerRepositorySummary> listRepositories(Tenant tenant, String compartmentId) {
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
        List<ContainerRepositorySummary> repositories = new ArrayList<>();

        try (ArtifactsClient artifactsClient = ArtifactsClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
            ListContainerRepositoriesRequest request = ListContainerRepositoriesRequest.builder()
                    .compartmentId(compartmentId)
                    // 可以设置状态过滤，例如只查 Available 的
                    .lifecycleState(ContainerRepository.LifecycleState.Available.getValue())
                    .build();

            ListContainerRepositoriesResponse response = artifactsClient.listContainerRepositories(request);
            if (response.getContainerRepositoryCollection() != null) {
                repositories = response.getContainerRepositoryCollection().getItems();
                log.info("成功获取 compartment: {} 下的镜像仓库，共 {} 个", compartmentId, repositories.size());
            }
        } catch (BmcException e) {
            log.error("获取镜像仓库列表失败, 状态码: {}, 错误信息: {}", e.getStatusCode(), e.getMessage(), e);
        } catch (Exception e) {
            log.error("获取镜像仓库列表出现异常", e);
        }
        return repositories;
    }

    /**
     * @Description: 获取指定镜像仓库下的所有镜像版本 (Tags/Images)
     * @Param: [tenant, compartmentId, repositoryName]
     * @return: java.util.List<com.oracle.bmc.artifacts.model.ContainerImageSummary>
     */
    public static List<ContainerImageSummary> listImages(Tenant tenant, String compartmentId, String repositoryName) {
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
        List<ContainerImageSummary> images = new ArrayList<>();

        try (ArtifactsClient artifactsClient = ArtifactsClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
            ListContainerImagesRequest request = ListContainerImagesRequest.builder()
                    .compartmentId(compartmentId)
                    .repositoryName(repositoryName)
                    .sortBy(ListContainerImagesRequest.SortBy.Timecreated) // 按创建时间排序
                    .sortOrder(ListContainerImagesRequest.SortOrder.Desc)
                    .build();

            ListContainerImagesResponse response = artifactsClient.listContainerImages(request);
            if (response.getContainerImageCollection() != null) {
                images = response.getContainerImageCollection().getItems();
                log.info("成功获取仓库 {} 下的镜像，共 {} 个", repositoryName, images.size());
            }
        } catch (Exception e) {
            log.error("获取镜像列表失败: 仓库名称: {}", repositoryName, e);
        }
        return images;
    }

    /**
     * @Description: 删除指定的容器镜像 (根据 Image OCID)
     * @Param: [tenant, imageId]
     * @return: boolean 删除成功返回true
     */
    public static boolean deleteImage(Tenant tenant, String imageId) {
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);

        try (ArtifactsClient artifactsClient = ArtifactsClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
            DeleteContainerImageRequest request = DeleteContainerImageRequest.builder()
                    .imageId(imageId)
                    .build();

            artifactsClient.deleteContainerImage(request);
            log.info("成功删除镜像，ImageID: {}", imageId);
            return true;
        } catch (BmcException e) {
            if (e.getStatusCode() == 404) {
                log.info("镜像 {} 已不存在，无需删除", imageId);
                return true;
            }
            log.error("删除镜像失败, ID: {}, 状态码: {}, 错误信息: {}", imageId, e.getStatusCode(), e.getMessage());
            return false;
        } catch (Exception e) {
            log.error("删除镜像时发生异常, ID: {}", imageId, e);
            return false;
        }
    }

    /**
     * @Description: 删除整个镜像仓库及其包含的所有镜像
     * 注意：如果仓库不为空，OCI 默认允许强制删除（视IAM权限而定）
     * @Param: [tenant, repositoryId]
     * @return: boolean
     */
    public static boolean deleteRepository(Tenant tenant, String repositoryId) {
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);

        try (ArtifactsClient artifactsClient = ArtifactsClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
            DeleteContainerRepositoryRequest request = DeleteContainerRepositoryRequest.builder()
                    .repositoryId(repositoryId)
                    .build();

            artifactsClient.deleteContainerRepository(request);
            log.info("成功发送删除镜像仓库请求，RepositoryID: {}", repositoryId);
            return true;
        } catch (BmcException e) {
            if (e.getStatusCode() == 404) {
                log.info("镜像仓库 {} 已不存在", repositoryId);
                return true;
            }
            log.error("删除镜像仓库失败, ID: {}", repositoryId, e);
            return false;
        } catch (Exception e) {
            log.error("删除镜像仓库发生异常, ID: {}", repositoryId, e);
            return false;
        }
    }

    /**
     * @Description: 自动化运维方法 - 清理旧镜像，仅保留最近的 N 个版本
     * @Param: [tenant, compartmentId, repositoryName, keepCount]
     * @return: int 实际删除的镜像数量
     */
    public static int cleanupOldImages(Tenant tenant, String compartmentId, String repositoryName, int keepCount) {
        log.info("开始清理仓库 {} 的旧镜像，保留最近的 {} 个", repositoryName, keepCount);

        List<ContainerImageSummary> allImages = listImages(tenant, compartmentId, repositoryName);
        if (allImages.size() <= keepCount) {
            log.info("仓库 {} 当前镜像数量 ({}) 未超过保留阈值 ({})，无需清理",
                    repositoryName, allImages.size(), keepCount);
            return 0;
        }

        // 确保按照创建时间倒序排列 (最新的在前)
        List<ContainerImageSummary> sortedImages = allImages.stream()
                .sorted(Comparator.comparing(ContainerImageSummary::getTimeCreated).reversed())
                .collect(Collectors.toList());

        // 截取需要删除的旧镜像子集
        List<ContainerImageSummary> imagesToDelete = sortedImages.subList(keepCount, sortedImages.size());

        int deletedCount = 0;
        for (ContainerImageSummary image : imagesToDelete) {
            String imageTag = (image.getVersion() != null) ? image.getVersion() : "no-tag";
            log.info("准备删除旧镜像: {} (ID: {}, 创建时间: {})", imageTag, image.getId(), image.getTimeCreated());

            boolean success = deleteImage(tenant, image.getId());
            if (success) {
                deletedCount++;
            }
        }

        log.info("清理完成。仓库 {} 共删除了 {} 个过期镜像", repositoryName, deletedCount);
        return deletedCount;
    }
}
