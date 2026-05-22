package com.doubledimple.ociserver.service.oracle.impl;

import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.OracleInstanceDetailRepository;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.ociserver.pojo.domain.dto.OciClassLoaderPojo;
import com.doubledimple.ociserver.utils.oracle.OciClassLoader;
import com.doubledimple.ociserver.service.oracle.BootVolumeService;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.utils.oracle.OciUtils;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.core.BlockstorageClient;
import com.oracle.bmc.core.ComputeClient;
import com.oracle.bmc.core.ComputeWaiters;
import com.oracle.bmc.core.model.AttachBootVolumeDetails;
import com.oracle.bmc.core.model.BootVolumeAttachment;
import com.oracle.bmc.core.model.BootVolumeSourceFromBootVolumeDetails;
import com.oracle.bmc.core.model.CreateBootVolumeBackupDetails;
import com.oracle.bmc.core.model.CreateBootVolumeDetails;
import com.oracle.bmc.core.model.Image;
import com.oracle.bmc.core.model.Instance;
import com.oracle.bmc.core.model.UpdateInstanceDetails;
import com.oracle.bmc.core.requests.AttachBootVolumeRequest;
import com.oracle.bmc.core.requests.CreateBootVolumeBackupRequest;
import com.oracle.bmc.core.requests.CreateBootVolumeRequest;
import com.oracle.bmc.core.requests.DeleteBootVolumeRequest;
import com.oracle.bmc.core.requests.DetachBootVolumeRequest;
import com.oracle.bmc.core.requests.GetBootVolumeAttachmentRequest;
import com.oracle.bmc.core.requests.GetBootVolumeRequest;
import com.oracle.bmc.core.requests.GetInstanceRequest;
import com.oracle.bmc.core.requests.InstanceActionRequest;
import com.oracle.bmc.core.requests.ListBootVolumeAttachmentsRequest;
import com.oracle.bmc.core.requests.ListImagesRequest;
import com.oracle.bmc.core.requests.UpdateInstanceRequest;
import com.oracle.bmc.core.responses.AttachBootVolumeResponse;
import com.oracle.bmc.core.responses.CreateBootVolumeBackupResponse;
import com.oracle.bmc.core.responses.CreateBootVolumeResponse;
import com.oracle.bmc.core.responses.GetBootVolumeAttachmentResponse;
import com.oracle.bmc.core.responses.GetBootVolumeResponse;
import com.oracle.bmc.core.responses.GetInstanceResponse;
import com.oracle.bmc.core.responses.ListBootVolumeAttachmentsResponse;
import com.oracle.bmc.core.responses.ListImagesResponse;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import javax.annotation.Resource;
import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.util.Base64;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.TimeUnit;

import static com.doubledimple.ociserver.config.constant.SystemScriptShell.getShell;
import static com.doubledimple.ociserver.pojo.enums.OperationSystemEnum.UBUNTU_20_04;

/**
 * 引导卷管理类
 */
@Service
@Slf4j
public class BootVolumeServiceImpl implements BootVolumeService {

    @Resource
    private OracleInstanceDetailRepository oracleInstanceDetailRepository;

    @Resource
    private TenantRepository tenantRepository;

    @Resource
    private OciClassLoader ociClassLoader;

    private static final long NEW_BOOT_VOLUME_SIZE_GB = 50L; // 新引导卷大小

    private static final String ROOT_PASSWORD = "oci-start"; // 临时root密码，首次登录后请更改


    /**
    * @Description: handleShrink
    *
     * 1.实例的id [instance-id]
     * 2.一个正常引导卷的id [source-boot-volume-id]
     * 3.租户id/区间id(适用于机器在区间内) [compartment-id]
     * 4. 一个删除引导卷的机器或者需要把引导卷改小的机器
     * oci bv boot-volume create --availability-domain [domain] --compartment-id [compartment-id] --size-in-gbs 50 --source-boot-volume-id [source-boot-volume-id]
     * 执行完，复制下其中的id值作为boot-volume-id 创建的新引导卷，点进去复制他的ocid也是boot-volume-id
    */
    @Override
    public ApiResponse handleShrink(String instanceDetailId, Long diskNum) {
        Long aLong = Long.valueOf(instanceDetailId);
        InstanceDetails instanceDetails = oracleInstanceDetailRepository.findById(aLong).get();
        long tenantId = instanceDetails.getTenantId();
        String shape = instanceDetails.getShape();
        String instanceId = instanceDetails.getInstanceId();
        Tenant tenant = tenantRepository.findById(tenantId).get();
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
        String compartmentId = provider.getTenantId();

        try (ComputeClient computeClient = ComputeClient.builder().build(provider);
             BlockstorageClient blockstorageClient = BlockstorageClient.builder().build(provider)) {

            System.out.println("\n步骤1: 获取需要缩小的实例详情");
            Instance armInstance = getInstance(computeClient, instanceId);
            String availabilityDomain = armInstance.getAvailabilityDomain();

            // 获取兼容的操作系统镜像 (ARM 和 AMD)
            System.out.println("\n步骤2: 获取兼容的操作系统镜像");
            String armImageId = getImageId(shape, computeClient, compartmentId);
            String amdImageId = getAmdImageId(computeClient, compartmentId);

            // 停止 ARM 实例
            System.out.println("\n步骤3: 停止 ARM 实例");
            if (!"STOPPED".equals(armInstance.getLifecycleState().getValue())) {
                stopInstance(computeClient, instanceId);
            }

            // 找到并分离当前 实例 引导卷
            System.out.println("\n步骤4: 找到并分离当前 ARM 引导卷");
            String armBootVolumeId = findBootVolumeId(computeClient, instanceId, availabilityDomain);
            detachBootVolume(computeClient, armBootVolumeId, instanceId);

            // ✅ 查看当前租户下是否存在amd实例


            // ✅ 将新引导卷挂载到 AMD 实例上
            System.out.println("\n步骤6: 挂载新引导卷到 AMD 实例");
            attachBootVolume(computeClient, "newBootVolumeId", instanceId);

            // ✅ 复制 ARM 数据到 AMD 新引导卷
            System.out.println("\n步骤7: 复制 ARM 数据到新卷");
            copyDataBetweenVolumes();

            // ✅ 更新 GRUB 和 fstab
            System.out.println("\n步骤8: 更新引导配置");
            updateGrubAndFstab();

            // ✅ 在 ARM 实例中挂载新引导卷
            System.out.println("\n步骤9: 挂载新引导卷到 ARM 实例");
            attachBootVolume(computeClient, "newBootVolumeId", instanceId);

            // ✅ 启动 ARM 实例
            System.out.println("\n步骤10: 启动 ARM 实例");
            startInstanceWithUserData(computeClient, instanceId);

            // ✅ 删除旧的引导卷
            System.out.println("\n步骤11: 删除旧引导卷");
            deleteBootVolume(blockstorageClient, armBootVolumeId);

            System.out.println("\n✅ 完成引导卷缩小！");

        } catch (Exception e) {
            throw new RuntimeException(e);
        }
        return ApiResponse.success();
    }



    // 获取实例
    private static Instance getInstance(ComputeClient client, String instanceId) throws Exception {
        GetInstanceRequest request = GetInstanceRequest.builder()
                .instanceId(instanceId)
                .build();

        GetInstanceResponse response = client.getInstance(request);
        System.out.println("实例信息: " + response.getInstance().getDisplayName());
        return response.getInstance();
    }

    // 获取ARM兼容的镜像ID
    private static String getImageId(String shape,ComputeClient client, String compartmentId) throws Exception {
        // 列出可用的平台镜像
        ListImagesRequest request = ListImagesRequest.builder()
                .compartmentId(compartmentId)
                .shape(shape)
                .operatingSystem(UBUNTU_20_04.getType())
                .limit(1)
                .sortBy(ListImagesRequest.SortBy.Timecreated)
                .sortOrder(ListImagesRequest.SortOrder.Desc)
                .build();

        ListImagesResponse response = client.listImages(request);
        List<Image> images = response.getItems();

        if (images == null || images.isEmpty()) {
            throw new Exception("找不到兼容的操作系统镜像");
        }

        String imageId = images.get(0).getId();
        System.out.println("使用兼容的操作系统镜像ID: " + imageId);
        return imageId;
    }

    // 停止实例
    private static void stopInstance(ComputeClient client, String instanceId) throws Exception {
        InstanceActionRequest request = InstanceActionRequest.builder()
                .instanceId(instanceId)
                .action("STOP")
                .build();

        System.out.println("正在停止实例...");
        client.instanceAction(request);

        // 等待实例停止
        ComputeWaiters waiter = client.getWaiters();
        GetInstanceRequest getRequest = GetInstanceRequest.builder()
                .instanceId(instanceId)
                .build();

        waiter.forInstance(getRequest, Instance.LifecycleState.Stopped)
                .execute();

        System.out.println("实例已停止");
    }

    // 查找引导卷ID
    private static String findBootVolumeId(ComputeClient client, String instanceId, String availabilityDomain) throws Exception {
        ListBootVolumeAttachmentsRequest request = ListBootVolumeAttachmentsRequest.builder()
                .instanceId(instanceId)
                .availabilityDomain(availabilityDomain)
                .build();

        ListBootVolumeAttachmentsResponse response = client.listBootVolumeAttachments(request);
        List<BootVolumeAttachment> attachments = response.getItems();

        if (attachments == null || attachments.isEmpty()) {
            throw new Exception("找不到实例的引导卷连接");
        }

        String bootVolumeId = attachments.get(0).getBootVolumeId();
        System.out.println("找到引导卷ID: " + bootVolumeId);
        return bootVolumeId;
    }

    // 分离引导卷
    private static void detachBootVolume(ComputeClient client, String bootVolumeId, String instanceId) throws Exception {
        // 先找到引导卷附件ID
        ListBootVolumeAttachmentsRequest listRequest = ListBootVolumeAttachmentsRequest.builder()
                .bootVolumeId(bootVolumeId)
                .instanceId(instanceId)
                .build();

        ListBootVolumeAttachmentsResponse listResponse = client.listBootVolumeAttachments(listRequest);
        if (listResponse.getItems().isEmpty()) {
            throw new Exception("找不到引导卷附件");
        }

        String attachmentId = listResponse.getItems().get(0).getId();

        // 分离引导卷
        DetachBootVolumeRequest detachRequest = DetachBootVolumeRequest.builder()
                .bootVolumeAttachmentId(attachmentId)
                .build();

        System.out.println("正在分离引导卷...");
        client.detachBootVolume(detachRequest);

        // 等待分离完成
        waitForBootVolumeDetachment(client, attachmentId);
    }

    // 等待引导卷分离完成
    private static void waitForBootVolumeDetachment(ComputeClient client, String attachmentId) throws Exception {
        boolean isDetached = false;
        int attempts = 0;

        while (!isDetached && attempts < 30) {
            attempts++;
            try {
                GetBootVolumeAttachmentRequest request = GetBootVolumeAttachmentRequest.builder()
                        .bootVolumeAttachmentId(attachmentId)
                        .build();

                GetBootVolumeAttachmentResponse response = client.getBootVolumeAttachment(request);
                String state = response.getBootVolumeAttachment().getLifecycleState().getValue();

                if ("DETACHED".equals(state)) {
                    isDetached = true;
                    System.out.println("引导卷已分离");
                } else if ("DETACHING".equals(state)) {
                    System.out.println("引导卷正在分离...(" + attempts + "/30)");
                    TimeUnit.SECONDS.sleep(10);
                } else {
                    throw new Exception("引导卷分离状态异常: " + state);
                }
            } catch (Exception e) {
                // 如果无法获取附件，可能已经分离完成
                if (e.getMessage().contains("NotFound")) {
                    isDetached = true;
                    System.out.println("引导卷已完全分离");
                } else {
                    throw e;
                }
            }
        }

        if (!isDetached) {
            throw new Exception("等待引导卷分离超时");
        }

        // 为确保完全分离，额外等待
        TimeUnit.SECONDS.sleep(20);
    }

    // 删除引导卷
    private static void deleteBootVolume(BlockstorageClient client, String bootVolumeId) throws Exception {
        DeleteBootVolumeRequest request = DeleteBootVolumeRequest.builder()
                .bootVolumeId(bootVolumeId)
                .build();

        System.out.println("正在删除原引导卷...");
        client.deleteBootVolume(request);

        // 等待引导卷删除
        waitForBootVolumeDeleted(client, bootVolumeId);
    }

    // 等待引导卷删除完成
    private static void waitForBootVolumeDeleted(BlockstorageClient client, String bootVolumeId) throws Exception {
        boolean isDeleted = false;
        int attempts = 0;

        while (!isDeleted && attempts < 30) {
            attempts++;
            try {
                GetBootVolumeRequest request = GetBootVolumeRequest.builder()
                        .bootVolumeId(bootVolumeId)
                        .build();

                GetBootVolumeResponse response = client.getBootVolume(request);
                String state = response.getBootVolume().getLifecycleState().getValue();

                if ("TERMINATED".equals(state)) {
                    isDeleted = true;
                    System.out.println("引导卷已删除");
                } else if ("TERMINATING".equals(state)) {
                    System.out.println("引导卷正在删除...(" + attempts + "/30)");
                    TimeUnit.SECONDS.sleep(10);
                } else {
                    throw new Exception("引导卷删除状态异常: " + state);
                }
            } catch (Exception e) {
                // 如果无法获取引导卷，可能已经删除完成
                if (e.getMessage().contains("NotFound")) {
                    isDeleted = true;
                    System.out.println("引导卷已完全删除");
                } else {
                    throw e;
                }
            }
        }

        if (!isDeleted) {
            throw new Exception("等待引导卷删除超时");
        }

        // 为确保完全释放资源，额外等待
        TimeUnit.SECONDS.sleep(20);
    }

    // 创建新的引导卷
    private static String createBootVolumeBackup(BlockstorageClient client, String bootVolumeId,
                                                 String compartmentId) throws Exception {
        // 创建备份请求
        CreateBootVolumeBackupDetails backupDetails = CreateBootVolumeBackupDetails.builder()
                .bootVolumeId(bootVolumeId)
                .displayName("Backup-BootVolume-" + System.currentTimeMillis())
                .type(CreateBootVolumeBackupDetails.Type.Full)
                .build();

        CreateBootVolumeBackupRequest request = CreateBootVolumeBackupRequest.builder()
                .createBootVolumeBackupDetails(backupDetails)
                .build();

        System.out.println("正在创建引导卷备份...");
        CreateBootVolumeBackupResponse response = client.createBootVolumeBackup(request);
        String backupId = response.getBootVolumeBackup().getId();

        // 等待备份完成
        // ... [等待备份完成的代码]

        return backupId;
    }

    // 等待引导卷变为可用
    private static void waitForBootVolumeAvailable(BlockstorageClient client, String bootVolumeId) throws Exception {
        boolean isAvailable = false;
        int attempts = 0;

        while (!isAvailable && attempts < 60) {
            attempts++;
            GetBootVolumeRequest request = GetBootVolumeRequest.builder()
                    .bootVolumeId(bootVolumeId)
                    .build();

            GetBootVolumeResponse response = client.getBootVolume(request);
            String state = response.getBootVolume().getLifecycleState().getValue();

            if ("AVAILABLE".equals(state)) {
                isAvailable = true;
                System.out.println("新引导卷已可用");
            } else if ("PROVISIONING".equals(state)) {
                System.out.println("引导卷正在创建中...(" + attempts + "/60)");
                TimeUnit.SECONDS.sleep(10);
            } else {
                throw new Exception("引导卷状态异常: " + state);
            }
        }

        if (!isAvailable) {
            throw new Exception("等待引导卷变为可用超时");
        }
    }

    // 挂载引导卷到实例
    private static void attachBootVolume(ComputeClient client, String bootVolumeId, String instanceId) throws Exception {
        AttachBootVolumeDetails attachDetails = AttachBootVolumeDetails.builder()
                .bootVolumeId(bootVolumeId)
                .instanceId(instanceId)
                .displayName("New-Boot-Volume-Attachment")
                .build();

        AttachBootVolumeRequest request = AttachBootVolumeRequest.builder()
                .attachBootVolumeDetails(attachDetails)
                .build();

        System.out.println("正在挂载新引导卷...");
        AttachBootVolumeResponse response = client.attachBootVolume(request);
        String attachmentId = response.getBootVolumeAttachment().getId();

        // 等待挂载完成
        waitForBootVolumeAttachment(client, attachmentId);
    }

    // 等待引导卷挂载完成
    private static void waitForBootVolumeAttachment(ComputeClient client, String attachmentId) throws Exception {
        boolean isAttached = false;
        int attempts = 0;

        while (!isAttached && attempts < 30) {
            attempts++;
            GetBootVolumeAttachmentRequest request = GetBootVolumeAttachmentRequest.builder()
                    .bootVolumeAttachmentId(attachmentId)
                    .build();

            GetBootVolumeAttachmentResponse response = client.getBootVolumeAttachment(request);
            String state = response.getBootVolumeAttachment().getLifecycleState().getValue();

            if ("ATTACHED".equals(state)) {
                isAttached = true;
                System.out.println("新引导卷已挂载");
            } else if ("ATTACHING".equals(state)) {
                System.out.println("引导卷正在挂载...(" + attempts + "/30)");
                TimeUnit.SECONDS.sleep(10);
            } else {
                throw new Exception("引导卷挂载状态异常: " + state);
            }
        }

        if (!isAttached) {
            throw new Exception("等待引导卷挂载超时");
        }
    }

    // 启动实例并应用用户数据
    private static void startInstanceWithUserData(ComputeClient client, String instanceId) throws Exception {
        // 首先更新实例的用户数据
        String encodedCloudInitScript = Base64.getEncoder().encodeToString(getShell(ROOT_PASSWORD).getBytes());
        UpdateInstanceRequest updateRequest = UpdateInstanceRequest.builder()
                .instanceId(instanceId)
                .updateInstanceDetails(
                        UpdateInstanceDetails.builder()
                                .metadata(Collections.singletonMap("user_data", encodedCloudInitScript))
                                .build()).build();

        System.out.println("更新实例配置，添加root登录脚本...");
        client.updateInstance(updateRequest);

        // 然后启动实例
        InstanceActionRequest request = InstanceActionRequest.builder()
                .instanceId(instanceId)
                .action("START")
                .build();

        System.out.println("正在启动实例...");
        client.instanceAction(request);

        // 等待实例启动
        ComputeWaiters waiter = client.getWaiters();
        GetInstanceRequest getRequest = GetInstanceRequest.builder()
                .instanceId(instanceId)
                .build();

        waiter.forInstance(getRequest, Instance.LifecycleState.Running)
                .execute();

        System.out.println("实例已启动");
        System.out.println("root登录配置将在系统启动过程中应用");

        // 给配置脚本一些时间运行
        System.out.println("等待root登录配置完成...");
        TimeUnit.SECONDS.sleep(60);
    }

    private static String createAmdBootVolume(BlockstorageClient client, String compartmentId,
                                              String availabilityDomain, String amdImageId,
                                              long sizeInGB) throws Exception {
        CreateBootVolumeDetails bootVolumeDetails = CreateBootVolumeDetails.builder()
                .availabilityDomain(availabilityDomain)
                .compartmentId(compartmentId)
                .sourceDetails(BootVolumeSourceFromBootVolumeDetails.builder()
                        .id(amdImageId)
                        .build())
                .sizeInGBs(sizeInGB)
                .build();

        CreateBootVolumeRequest request = CreateBootVolumeRequest.builder()
                .createBootVolumeDetails(bootVolumeDetails)
                .build();

        CreateBootVolumeResponse response = client.createBootVolume(request);
        String newBootVolumeId = response.getBootVolume().getId();

        waitForBootVolumeAvailable(client, newBootVolumeId);
        return newBootVolumeId;
    }

    private static void copyDataBetweenVolumes() throws Exception {
        executeCommand("mkdir -p /mnt/old-volume");
        executeCommand("mkdir -p /mnt/new-volume");
        executeCommand("mount /dev/sda1 /mnt/old-volume");
        executeCommand("mount /dev/sdb1 /mnt/new-volume");

        executeCommand("rsync -aAXv /mnt/old-volume/ /mnt/new-volume/ --exclude={\"/dev/*\",\"/proc/*\",\"/sys/*\",\"/tmp/*\",\"/run/*\",\"/mnt/*\",\"/media/*\",\"/lost+found\"}");
    }

    private static void updateGrubAndFstab() throws Exception {
        executeCommand("blkid");
        executeCommand("vi /mnt/new-volume/etc/fstab");
        executeCommand("grub-install /dev/sdb");
        executeCommand("update-grub");
    }

    private static String getAmdImageId(ComputeClient client, String compartmentId) throws Exception {
        ListImagesRequest request = ListImagesRequest.builder()
                .compartmentId(compartmentId)
                .shape("VM.Standard2.1") // AMD 兼容 Shape
                .operatingSystem(UBUNTU_20_04.getType())
                .limit(1)
                .sortBy(ListImagesRequest.SortBy.Timecreated)
                .sortOrder(ListImagesRequest.SortOrder.Desc)
                .build();

        ListImagesResponse response = client.listImages(request);
        List<Image> images = response.getItems();

        if (images == null || images.isEmpty()) {
            throw new Exception("找不到兼容的 AMD 镜像");
        }

        return images.get(0).getId();
    }

    private static void executeCommand(String command) throws Exception {
        log.info("Executing command: {}", command);
        Process process;
        try {
            process = Runtime.getRuntime().exec(new String[]{"/bin/bash", "-c", command});
            process.waitFor();

            BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()));
            String line;
            while ((line = reader.readLine()) != null) {
                log.info(line);
            }

            BufferedReader errorReader = new BufferedReader(new InputStreamReader(process.getErrorStream()));
            while ((line = errorReader.readLine()) != null) {
                log.error(line);
            }

            if (process.exitValue() != 0) {
                throw new Exception("Command execution failed: " + command + ", exit code: " + process.exitValue());
            }
        } catch (IOException | InterruptedException e) {
            log.error("Error executing command: {}", command, e);
            throw new Exception("Error executing command: " + command, e);
        }
        log.info("Command executed successfully: {}", command);
    }



}
