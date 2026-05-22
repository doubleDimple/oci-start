package com.doubledimple.ociserver.utils.oracle;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ociserver.pojo.enums.ArchitectureEnum;
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.core.BlockstorageClient;
import com.oracle.bmc.core.model.BootVolume;
import com.oracle.bmc.core.model.BootVolumeBackup;
import com.oracle.bmc.core.model.BootVolumeSourceFromBootVolumeBackupDetails;
import com.oracle.bmc.core.model.CopyBootVolumeBackupDetails;
import com.oracle.bmc.core.model.CreateBootVolumeBackupDetails;
import com.oracle.bmc.core.model.CreateBootVolumeDetails;
import com.oracle.bmc.core.requests.CopyBootVolumeBackupRequest;
import com.oracle.bmc.core.requests.CreateBootVolumeBackupRequest;
import com.oracle.bmc.core.requests.CreateBootVolumeRequest;
import com.oracle.bmc.core.requests.GetBootVolumeBackupRequest;
import com.oracle.bmc.core.requests.ListBootVolumeBackupsRequest;
import com.oracle.bmc.core.responses.CopyBootVolumeBackupResponse;
import lombok.extern.slf4j.Slf4j;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static com.doubledimple.ociserver.utils.oracle.OciUtils.getProvider;

/**
 * @version 1.0.0
 * @ClassName OciBackUpUtils
 * @Description 备份操作
 * @Author doubleDimple
 * @Date 2025-04-03 10:08
 */
@Slf4j
public class OciBackUpUtils {

    public static final String ARCHITECTURE_TYPE_KEY = "ArchitectureType";
    public static final String ARCHITECTURE_ARM_NAME = ArchitectureEnum.ARM.getBackUpName();
    public static final String ARCHITECTURE_AMD_NAME = ArchitectureEnum.AMD.getBackUpName();

    public static final Map<String, String> FREE_ARM_TAG = new HashMap<>();
    public static final Map<String, String> FREE_AMD_TAG = new HashMap<>();

    static {
        FREE_ARM_TAG.put(ARCHITECTURE_TYPE_KEY, ARCHITECTURE_ARM_NAME);
        FREE_AMD_TAG.put(ARCHITECTURE_TYPE_KEY, ARCHITECTURE_AMD_NAME);
    }


    /**
     * 查询当前租户下主区域是否存在引导卷备份
     * @param tenant 身份验证提供程序
     * @param architectureType 架构类型，"ARM"或"AMD"
     * @return 如果存在备份则返回对应的备份引导卷，否则返回null
     */
    public static BootVolumeBackup hasBootVolumeBackup(Tenant tenant, String architectureType) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        String compartmentId = provider.getTenantId();
        try (BlockstorageClient blockstorageClient = BlockstorageClient.builder().build(provider)) {
            // 查询引导卷备份列表
            ListBootVolumeBackupsRequest listRequest =
                    ListBootVolumeBackupsRequest.builder()
                            .compartmentId(compartmentId)
                            .lifecycleState(BootVolumeBackup.LifecycleState.Available)
                            .build();

            List<BootVolumeBackup> backups =
                    blockstorageClient.listBootVolumeBackups(listRequest).getItems();

            return backups.stream()
                    .filter(backup -> {
                        Map<String, String> backupTags = backup.getFreeformTags();
                        // 获取备份中的类型值
                        String actualType = backupTags.get(ARCHITECTURE_TYPE_KEY);
                        // 比较两个值是否相等
                        return architectureType.equalsIgnoreCase(actualType);
                    })
                    .findFirst()
                    .orElse(null);

        } catch (Exception e) {
            log.error("查询引导卷备份时出错", e);
            return null;
        }
    }


    /**
     * 生成引导卷备份
     * @param tenant 身份验证提供程序
     * @param bootVolumeId 需要备份的引导卷ID
     * @param architectureType 架构类型，"ARM"或"AMD"
     * @return 返回创建的引导卷备份ID，如果创建失败则返回null
     */
    public static String createBootVolumeBackup(Tenant tenant,
                                                String bootVolumeId,
                                                String architectureType) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        BootVolumeBackup bootVolumeBackup = hasBootVolumeBackup(tenant, architectureType);
        if (bootVolumeBackup != null){
            return bootVolumeBackup.getId();
        }
        try (BlockstorageClient blockstorageClient = BlockstorageClient.builder().build(provider)) {
            String backupDisplayName = architectureType;
            Map<String, String> tagMapByArchitectureType = getTagMapByArchitectureType(architectureType);
            // 创建备份请求
            CreateBootVolumeBackupDetails createDetails =
                    CreateBootVolumeBackupDetails.builder()
                            .bootVolumeId(bootVolumeId)
                            .displayName(architectureType)
                            .freeformTags(tagMapByArchitectureType)
                            .type(CreateBootVolumeBackupDetails.Type.Full)
                            .build();

            CreateBootVolumeBackupRequest createRequest =
                    CreateBootVolumeBackupRequest.builder()
                            .createBootVolumeBackupDetails(createDetails)
                            .build();

            // 发送创建请求
            BootVolumeBackup backup =
                    blockstorageClient.createBootVolumeBackup(createRequest).getBootVolumeBackup();

            String backupId = backup.getId();
            log.debug("开始创建引导卷备份: {}, ID: {}", backupDisplayName, backupId);

            // 等待备份变为可用状态
            final int MAX_WAIT_ATTEMPTS = 60;
            final int WAIT_INTERVAL_SECONDS = 30;

            for (int attempt = 0; attempt < MAX_WAIT_ATTEMPTS; attempt++) {
                GetBootVolumeBackupRequest getRequest =
                        GetBootVolumeBackupRequest.builder()
                                .bootVolumeBackupId(backupId)
                                .build();

                BootVolumeBackup currentBackup =
                        blockstorageClient.getBootVolumeBackup(getRequest).getBootVolumeBackup();

                BootVolumeBackup.LifecycleState state = currentBackup.getLifecycleState();
                log.info("引导卷备份状态: {}, 尝试次数: {}/{}",
                        state,
                        attempt + 1,
                        MAX_WAIT_ATTEMPTS);

                if (state == BootVolumeBackup.LifecycleState.Available) {
                    log.debug("引导卷备份创建成功: {}", backupId);
                    return backupId;
                } else if (state == BootVolumeBackup.LifecycleState.Faulty ||
                        state == BootVolumeBackup.LifecycleState.Terminated) {
                    log.warn("引导卷备份创建失败: {}", backupId);
                    return null;
                }
                try {
                    Thread.sleep(WAIT_INTERVAL_SECONDS * 1000);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    log.warn("等待备份创建过程被中断");
                    break;
                }
            }
            return backupId;
        } catch (Exception e) {
            log.warn("创建引导卷备份时出错,原因为:{}", e.getMessage());
            return null;
        }
    }


    /**
     * 从备份创建引导卷
     *
     * @param tenant             租户信息
     * @param region             OCI区域
     * @param backupId           备份ID
     * @param availabilityDomain 可用性域
     * @return 创建的引导卷ID，如果创建失败则返回null
     */
    public static String createBootVolumeFromBackup(Tenant tenant,
                                                    String region,
                                                    String backupId,
                                                    String availabilityDomain) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        String compartmentId = provider.getTenantId();
        try (BlockstorageClient blockstorageClient = BlockstorageClient.builder()
                .region(Region.fromRegionId(region))
                .build(provider)) {

            // 创建引导卷请求
            CreateBootVolumeDetails createDetails =
                    CreateBootVolumeDetails.builder()
                            .availabilityDomain(availabilityDomain)
                            .compartmentId(compartmentId)
                            .displayName("OCI-START-BOOT_VOLUME"+System.currentTimeMillis())
                            .sourceDetails(BootVolumeSourceFromBootVolumeBackupDetails.builder()
                                    .id(backupId)
                                    .build()).build();

            CreateBootVolumeRequest createRequest =
                    CreateBootVolumeRequest.builder()
                            .createBootVolumeDetails(createDetails)
                            .build();

            // 发送创建请求
            BootVolume bootVolume =
                    blockstorageClient.createBootVolume(createRequest).getBootVolume();

            String bootVolumeId = bootVolume.getId();
            log.info("开始从备份创建新引导卷: ID: {}, 区域: {}, 可用性域: {}",
                     bootVolumeId, region, availabilityDomain);

            // 等待引导卷变为可用状态
            return waitForBootVolumeAvailability(blockstorageClient, bootVolumeId);
        } catch (Exception e) {
            log.error("从备份创建引导卷时出错: 区域: {}, 可用性域: {}, 错误: {}",
                    region, availabilityDomain, e.getMessage(), e);
            return null;
        }
    }

    /**
     * 等待引导卷变为可用状态
     *
     * @param blockstorageClient 存储客户端
     * @param bootVolumeId 引导卷ID
     * @return 引导卷ID，如果创建失败则返回null
     */
    private static String waitForBootVolumeAvailability(BlockstorageClient blockstorageClient, String bootVolumeId) {
        final int MAX_WAIT_ATTEMPTS = 40; // 最多等待40次
        final int WAIT_INTERVAL_SECONDS = 15; // 每次等待15秒

        for (int attempt = 0; attempt < MAX_WAIT_ATTEMPTS; attempt++) {
            com.oracle.bmc.core.requests.GetBootVolumeRequest getRequest =
                    com.oracle.bmc.core.requests.GetBootVolumeRequest.builder()
                            .bootVolumeId(bootVolumeId)
                            .build();

            BootVolume currentVolume =
                    blockstorageClient.getBootVolume(getRequest).getBootVolume();

            BootVolume.LifecycleState state = currentVolume.getLifecycleState();
            log.info("引导卷状态: {}, 尝试次数: {}/{}", state, attempt + 1, MAX_WAIT_ATTEMPTS);

            if (state == BootVolume.LifecycleState.Available) {
                log.info("引导卷创建成功: {}", bootVolumeId);
                return bootVolumeId;
            } else if (state == BootVolume.LifecycleState.Faulty ||
                    state == BootVolume.LifecycleState.Terminated) {
                log.error("引导卷创建失败: {}", bootVolumeId);
                return null;
            }

            try {
                Thread.sleep(WAIT_INTERVAL_SECONDS * 1000);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                log.warn("等待引导卷创建过程被中断");
                break;
            }
        }

        log.warn("引导卷创建超时，请手动检查状态: {}", bootVolumeId);
        return bootVolumeId;
    }

    public static Map<String, String> getTagMapByArchitectureType(String architectureType) {
        if (ARCHITECTURE_ARM_NAME.equalsIgnoreCase(architectureType)) {
            return FREE_ARM_TAG;
        } else if (ARCHITECTURE_AMD_NAME.equalsIgnoreCase(architectureType)) {
            return FREE_AMD_TAG;
        }
        return null;
    }

    /**
     * 删除引导卷备份
     *
     * @param tenant 租户信息
     * @param bootVolumeBackupId 备份ID
     * @return 是否删除成功
     */
    public static boolean deleteBootVolumeBackup(Tenant tenant, String bootVolumeBackupId) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        try (BlockstorageClient blockstorageClient = BlockstorageClient.builder().build(provider)) {
            // 首先检查备份是否存在
            GetBootVolumeBackupRequest getRequest =
                    GetBootVolumeBackupRequest.builder()
                            .bootVolumeBackupId(bootVolumeBackupId)
                            .build();

            try {
                BootVolumeBackup backup =
                        blockstorageClient.getBootVolumeBackup(getRequest).getBootVolumeBackup();

                if (backup.getLifecycleState() == BootVolumeBackup.LifecycleState.Terminated) {
                    log.debug("备份已经被删除: {}", bootVolumeBackupId);
                    return true;
                }
            } catch (Exception e) {
                log.warn("查询备份状态时出错，可能备份不存在: {}", bootVolumeBackupId);
                return false;
            }

            // 创建删除请求
            com.oracle.bmc.core.requests.DeleteBootVolumeBackupRequest deleteRequest =
                    com.oracle.bmc.core.requests.DeleteBootVolumeBackupRequest.builder()
                            .bootVolumeBackupId(bootVolumeBackupId)
                            .build();

            // 发送删除请求
            blockstorageClient.deleteBootVolumeBackup(deleteRequest);
            log.info("已发送删除引导卷备份请求: {}", bootVolumeBackupId);

            // 等待备份被删除
            final int MAX_WAIT_ATTEMPTS = 20;
            final int WAIT_INTERVAL_SECONDS = 10;

            for (int attempt = 0; attempt < MAX_WAIT_ATTEMPTS; attempt++) {
                try {
                    BootVolumeBackup currentBackup =
                            blockstorageClient.getBootVolumeBackup(getRequest).getBootVolumeBackup();

                    BootVolumeBackup.LifecycleState state = currentBackup.getLifecycleState();
                    log.info("引导卷备份删除状态: {}, 尝试次数: {}/{}",
                            state,
                            attempt + 1,
                            MAX_WAIT_ATTEMPTS);

                    if (state == BootVolumeBackup.LifecycleState.Terminated) {
                        log.info("引导卷备份删除成功: {}", bootVolumeBackupId);
                        return true;
                    } else if (state == BootVolumeBackup.LifecycleState.Terminating) {
                        log.debug("引导卷备份正在删除中...");
                    } else {
                        log.warn("引导卷备份状态异常: {}", state);
                    }
                } catch (Exception e) {
                    // 如果查询出错，可能是因为备份已经被删除
                    if (e.getMessage().contains("NotFound") || e.getMessage().contains("not found")) {
                        log.info("引导卷备份已被删除: {}", bootVolumeBackupId);
                        return true;
                    }
                    log.warn("查询备份状态时出错: {}", e.getMessage());
                }

                try {
                    Thread.sleep(WAIT_INTERVAL_SECONDS * 1000);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    log.warn("等待备份删除过程被中断");
                    break;
                }
            }

            log.warn("引导卷备份删除超时，请手动检查状态: {}", bootVolumeBackupId);
            return false;
        } catch (Exception e) {
            log.error("删除引导卷备份时出错: {}", e.getMessage(), e);
            return false;
        }
    }

    /**
     * 复制引导卷备份到其他区域
     *
     * @param tenant 租户信息
     * @param sourceBackupId 源备份ID
     * @param sourceRegion 源区域
     * @param targetRegion 目标区域
     * @param architectureType 架构类型
     * @return 新创建的备份ID，如果失败则返回null
     */
    public static String copyBootVolumeBackupToRegion(Tenant tenant,
                                                      String sourceBackupId,
                                                      String sourceRegion,
                                                      String targetRegion,
                                                      String architectureType) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);

        try (BlockstorageClient sourceClient = BlockstorageClient.builder()
                .region(Region.fromRegionId(sourceRegion))
                .build(provider)) {

            tenant.setRegion(targetRegion);
            BootVolumeBackup bootVolumeBackup = hasBootVolumeBackup(tenant, architectureType);
            if (null != bootVolumeBackup){
                return bootVolumeBackup.getId();
            }

            // 获取源备份信息
            GetBootVolumeBackupRequest getRequest = GetBootVolumeBackupRequest.builder()
                    .bootVolumeBackupId(sourceBackupId)
                    .build();

            BootVolumeBackup sourceBackup = sourceClient.getBootVolumeBackup(getRequest).getBootVolumeBackup();

            // 检查源备份是否可用
            if (sourceBackup.getLifecycleState() != BootVolumeBackup.LifecycleState.Available) {
                log.warn("源备份不可用，当前状态: {}", sourceBackup.getLifecycleState());
                return null;
            }

            String backupDisplayName = architectureType;

            // 创建复制详情
            CopyBootVolumeBackupDetails copyDetails = CopyBootVolumeBackupDetails.builder()
                    .destinationRegion(targetRegion)
                    .displayName(backupDisplayName)
                    .build();

            // 创建复制请求
            CopyBootVolumeBackupRequest copyRequest = CopyBootVolumeBackupRequest.builder()
                    .bootVolumeBackupId(sourceBackupId)
                    .copyBootVolumeBackupDetails(copyDetails)
                    .build();

            // 发送复制请求
            CopyBootVolumeBackupResponse response = sourceClient.copyBootVolumeBackup(copyRequest);

            // 获取新创建的备份ID
            BootVolumeBackup newBackup = response.getBootVolumeBackup();
            String newBackupId = newBackup.getId();

            log.info("开始复制引导卷备份到目标区域: {}, 新备份ID: {}", targetRegion, newBackupId);

            // 等待跨区域复制完成
            return waitForCrossRegionBackupCompletion(tenant, newBackupId, targetRegion);

        } catch (Exception e) {
            log.error("复制引导卷备份时出错: {}", e.getMessage(), e);
            return null;
        }
    }

    /**
     * 等待跨区域备份复制完成
     *
     * @param tenant 租户信息
     * @param backupId 新备份ID
     * @param targetRegion 目标区域
     * @return 备份ID，如果失败则返回null
     */
    private static String waitForCrossRegionBackupCompletion(Tenant tenant,
                                                             String backupId,
                                                             String targetRegion) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);

        // 在目标区域创建客户端来检查备份状态
        try (BlockstorageClient targetClient = BlockstorageClient.builder()
                .region(Region.fromRegionId(targetRegion))
                .build(provider)) {

            final int MAX_WAIT_ATTEMPTS = 40;  // 跨区域复制可能需要更长时间
            final int WAIT_INTERVAL_SECONDS = 20;

            for (int attempt = 0; attempt < MAX_WAIT_ATTEMPTS; attempt++) {
                try {
                    GetBootVolumeBackupRequest getRequest =
                            GetBootVolumeBackupRequest.builder()
                                    .bootVolumeBackupId(backupId)
                                    .build();

                    BootVolumeBackup backup =
                            targetClient.getBootVolumeBackup(getRequest).getBootVolumeBackup();

                    BootVolumeBackup.LifecycleState state = backup.getLifecycleState();
                    log.info("跨区域备份复制状态: {}, 尝试次数: {}/{}",
                            state, attempt + 1, MAX_WAIT_ATTEMPTS);

                    if (state == BootVolumeBackup.LifecycleState.Available) {
                        log.info("引导卷备份跨区域复制成功: {}", backupId);
                        return backupId;
                    } else if (state == BootVolumeBackup.LifecycleState.Faulty ||
                            state == BootVolumeBackup.LifecycleState.Terminated) {
                        log.error("引导卷备份跨区域复制失败: {}", backupId);
                        return null;
                    }

                    Thread.sleep(WAIT_INTERVAL_SECONDS * 1000);
                } catch (Exception e) {
                    // 备份可能还在复制中，继续等待
                    log.debug("备份在目标区域还不可见或正在复制中: {}", e.getMessage());
                }
            }

            log.warn("引导卷备份跨区域复制超时，请手动检查状态: {}", backupId);
            return backupId;

        } catch (Exception e) {
            log.error("检查跨区域备份复制状态时出错: {}", e.getMessage(), e);
            return null;
        }
    }
}
