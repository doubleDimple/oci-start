package com.doubledimple.ociserver.service.impl;

import cn.hutool.core.collection.CollectionUtil;
import cn.hutool.core.util.IdUtil;
import com.alibaba.fastjson2.JSON;
import com.doubledimple.dao.entity.BootInstance;
import com.doubledimple.dao.entity.CloudTenancy;
import com.doubledimple.dao.entity.OciComputerInfo;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.BootInstanceRepository;
import com.doubledimple.dao.repository.CloudTenancyRepository;
import com.doubledimple.dao.repository.OciComputerInfoRepository;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.ocicommon.enums.RegionEnum;
import com.doubledimple.ociserver.config.task.CreateInstanceTaskV2;
import com.doubledimple.ociserver.pojo.domain.dto.User;
import com.doubledimple.ociserver.pojo.domain.query.BootInstanceQuery;
import com.doubledimple.ociserver.pojo.dto.OciComputerDto;
import com.doubledimple.ociserver.pojo.enums.MessageEnum;
import com.doubledimple.ociserver.pojo.enums.OperationSystemEnum;
import com.doubledimple.ociserver.pojo.request.ImageInfoReq;
import com.doubledimple.ociserver.pojo.response.ImageInfoRes;
import com.doubledimple.ociserver.service.message.factory.MessageFactory;
import com.doubledimple.ociserver.pojo.request.UpdateBootInstanceRequest;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.pojo.response.BootInstanceRes;
import com.doubledimple.ociserver.service.BootInstanceService;
import com.doubledimple.ociserver.utils.oracle.OciComputerUtils;
import com.doubledimple.ociserver.utils.oracle.OciImageUtils;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.beans.BeanUtils;
import org.springframework.data.domain.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.CollectionUtils;

import javax.annotation.Resource;
import java.sql.Timestamp;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ThreadPoolExecutor;

import static com.doubledimple.ocicommon.template.MessageTemplate.MESSAGE_CONFIG_STOP_NO_AUTH_TEMPLATE;
import static com.doubledimple.ocicommon.template.MessageTemplate.MESSAGE_CONFIG_SUCCESS_TEMPLATE;
import static com.doubledimple.ociserver.config.constant.GenPojoUtils.bootPojo;
import static java.lang.System.*;

/**
 * @author doubleDimple
 * @date 2024:10:08日 22:14
 */
@Service
@Slf4j
public class BootInstanceServiceImpl implements BootInstanceService {

    public static final int scanInterval = 10;

    @Resource
    private BootInstanceRepository bootInstanceRepository;

    @Resource
    private TenantRepository tenantRepository;


    @Resource
    MessageFactory messageFactory;

    @Resource
    CreateInstanceTaskV2 createInstanceTask;

    @Resource
    private CloudTenancyRepository cloudTenancyRepository;

    @Resource
    OciComputerInfoRepository ociComputerInfoRepository;

    @Resource
    ThreadPoolExecutor executor;

    @Transactional
    @Override
    public void saveBootInstance(BootInstance bootInstance) {
        String operatingSystem = bootInstance.getOperatingSystem();
        if (StringUtils.isBlank(operatingSystem)){
            OperationSystemEnum defaultSystemType = OperationSystemEnum.getDefaultSystemType();
            bootInstance.setOperatingSystem(defaultSystemType.getType());
            bootInstance.setOperatingSystemVersion(defaultSystemType.getVersion());
        }
        int instanceCount = bootInstance.getInstanceCount();
        List<BootInstance> bootInstances = new ArrayList<>(instanceCount);
        List<OciComputerInfo> ociComputerInfos = new ArrayList<>(instanceCount);
        // 获取当前时间
        LocalDateTime now = LocalDateTime.now();
        //这里执行创建实例的预创建
        Optional<Tenant> byId = tenantRepository.findById(bootInstance.getTenantId());
        if (!byId.isPresent()){
            return;
        }
        Tenant tenant = byId.get();
        //查询是否存在computerDto,不存在,再重新构建
        User user = bootPojo(tenant, bootInstance);
        Optional<OciComputerInfo> byBootId = ociComputerInfoRepository.findFirstByTenantIdAndArchitectureAndCloudTypeAndRegionOrderByIdDesc(bootInstance.getTenantId(), bootInstance.getArchitecture(), bootInstance.getCloudType(),user.getRegion());
        OciComputerDto ociComputerDto = null;
        if (!byBootId.isPresent()){
            ociComputerDto = OciComputerUtils.buildComputerParam(byId.get(), user);
        }else {
            ociComputerDto = JSON.parseObject(byBootId.get().getComputerCreateJson(), OciComputerDto.class);
        }
        List<OciComputerDto.AvailabilityDomainName> availabilityDomainNameList = ociComputerDto.getAvailabilityDomainNameList();
        if (CollectionUtils.isEmpty(availabilityDomainNameList)){
            log.warn("当前租户:{}未获取到可用域信息,此区域可能不支持开机",tenant.getTenancyName());
            return;
        }
        for ( int i = 0;i<instanceCount;i++){
            BootInstance bootInstanceAdd = new BootInstance();
            BeanUtils.copyProperties(bootInstance,bootInstanceAdd);
            bootInstanceAdd.setInstanceCount(1);
            String bootId = currentTimeMillis() + IdUtil.randomUUID();
            bootInstanceAdd.setBootId(bootId);
            if (bootInstance.getLoopTime() < 12){
                bootInstanceAdd.setLoopTime(12);
            }
            //计算下次执行时间
            int initialDelay = Math.max(bootInstanceAdd.getLoopTime(), scanInterval);
            Timestamp currentTime = new Timestamp(System.currentTimeMillis());
            Timestamp futureTime = new Timestamp(currentTime.getTime() + initialDelay * 1000L); // 20000毫秒 = 20秒
            bootInstanceAdd.setNextExecutionTime(futureTime);

            bootInstanceAdd.setCreatedAt(now);
            bootInstanceAdd.setUpdatedAt(now);
            bootInstanceAdd.setStatus(1);
            bootInstanceAdd.setLastResetDate(LocalDate.now());

            bootInstances.add(bootInstanceAdd);

            ociComputerDto.setBootIdStr(bootId);
            OciComputerInfo ociComputerInfo = new OciComputerInfo();
            ociComputerInfo.setTenantId(bootInstanceAdd.getTenantId());
            ociComputerInfo.setArchitecture(bootInstanceAdd.getArchitecture());
            ociComputerInfo.setBootIdStr(bootId);
            ociComputerInfo.setComputerCreateJson(JSON.toJSONString(ociComputerDto));
            ociComputerInfo.setRegion(user.getRegion());
            ociComputerInfos.add(ociComputerInfo);
        }
        bootInstanceRepository.saveAll(bootInstances);
        ociComputerInfoRepository.saveAll(ociComputerInfos);

        //发送信息
        CompletableFuture.runAsync(() ->
                messageFactory.getType(MessageEnum.TELEGRAM)
                        .sendMessageTemplate(String.format(MESSAGE_CONFIG_SUCCESS_TEMPLATE,tenant.getUserName(),RegionEnum.getRegionCode( tenant.getRegion()))),executor);
    }

    @Override
    public List<BootInstance> getAllTenants(long tenantId) {
        return bootInstanceRepository.queryBootInstanceByTenantId(tenantId);
    }

    @Transactional
    @Override
    public void startInstance(BootInstance bootInstance) {
        User user = bootPojo(
                tenantRepository.findById(bootInstance.getTenantId()).get(),
                bootInstance);

        bootInstanceRepository.updateBootInstanceStatusById(bootInstance.getId(),1);
        bootInstanceRepository.flush();

        //推送信息
        CompletableFuture.runAsync(() ->
                messageFactory.getType(MessageEnum.TELEGRAM)
                        .sendMessageTemplate(String.format(MESSAGE_CONFIG_SUCCESS_TEMPLATE,user.getUserName(),user.getRegion())));


    }

    @Transactional
    @Override
    public void stopBoot(BootInstance bootInstance) {

        User user = bootPojo(
                tenantRepository.findById(bootInstance.getTenantId()).get(),
                bootInstance);

        //taskRepository.deleteTask(bootInstance.getBootId());
        createInstanceTask.deleteTask(bootInstance.getBootId());

        //修改为未开机
        bootInstanceRepository.updateBootInstanceStatusById(bootInstance.getId(),0);
        bootInstanceRepository.flush();

        //taskRepository.doCommandTask();
        //createInstanceTask.loadAllPendingTasks();


        //CompletableFuture.runAsync(() ->messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplate(String.format(MESSAGE_CONFIG_STOP_TEMPLATE,user.getUserName(),user.getUniqueStrId())));

    }

    @Transactional
    @Override
    public void autoStopBoot(BootInstance bootInstance,String err) {

        User user = bootPojo(
                tenantRepository.findById(bootInstance.getTenantId()).get(),
                bootInstance);

        //taskRepository.deleteTask(bootInstance.getBootId());
        createInstanceTask.deleteTask(bootInstance.getBootId());

        //修改为未开机
        bootInstanceRepository.updateBootInstanceStatusById(bootInstance.getId(),0);
        bootInstanceRepository.flush();

        //taskRepository.doCommandTask();
        //createInstanceTask.loadAllPendingTasks();

        CompletableFuture.runAsync(() ->messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplate(String.format(MESSAGE_CONFIG_STOP_NO_AUTH_TEMPLATE,user.getUserName(),user.getUniqueStrId(), err)));

    }

    @Transactional
    @Override
    public void deleteBoot(BootInstance bootInstance) {
        User user = null;
        try {
            user = bootPojo(
                    tenantRepository.findById(bootInstance.getTenantId()).get(),
                    bootInstance);
        } catch (Exception e) {
            log.warn("用户不存在,后续继续删除,原因为:{}",e.getMessage());
        }
        createInstanceTask.deleteTask(bootInstance.getBootId());
        bootInstanceRepository.delete(bootInstance);
        bootInstanceRepository.flush();
        ociComputerInfoRepository.findByBootIdStr(bootInstance.getBootId()).ifPresent(ociComputerInfo -> ociComputerInfoRepository.deleteById(ociComputerInfo.getId()));
        /*try {
            if (user != null){
                messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplate(String.format(MESSAGE_CONFIG_STOP_TEMPLATE,user.getUserName(),user.getUniqueStrId()));
            }
        } catch (Exception e) {
            log.warn("消息发送失败,原因为:{}",e.getMessage());
        }*/
    }

    @Override
    public Page<BootInstanceRes> getAllBoots(int page,int size) {
        Pageable pageable = PageRequest.of(page, size);
        //Page<BootInstance> content = bootInstanceRepository.findAll(pageable);
        //log.info(JSON.toJSONString( content.getContent()));
        Page<BootInstance> content = bootInstanceRepository.findAllGroupedWithSumAddCount(null,pageable);
        return doResult(content);
    }

    @Override
    public Page<BootInstanceRes> findBootInstances(BootInstanceQuery query, Pageable pageable) {
        /*Specification<BootInstance> spec = (root, criteriaQuery, cb) -> {
            List<Predicate> predicates = new ArrayList<>();

            if (null != query.getTenantId()) {
                predicates.add(cb.equal(root.get("tenantId"), query.getTenantId()));
            }
            return predicates.isEmpty() ? null : cb.and(predicates.toArray(new Predicate[0]));
        };*/
        //Page<BootInstance> content = bootInstanceRepository.findAll(spec, pageable);
        return doResult(bootInstanceRepository.findAllGroupedWithSumAddCount(query.getTenantId(), pageable));
    }

    @Override
    public ApiResponse updateBootInstance(UpdateBootInstanceRequest request) {
        // 1. 参数校验
        if (request.getOcpu() == null || request.getOcpu() <= 0) {
            return ApiResponse.error("OCPU必须大于0");
        }
        if (request.getMemory() == null || request.getMemory() <= 0) {
            return ApiResponse.error("内存必须大于0");
        }
        if (request.getDisk() == null || request.getDisk() <= 0) {
            return ApiResponse.error("磁盘必须大于0");
        }
        if (request.getLoopTime() == null || request.getLoopTime() <= 0) {
            return ApiResponse.error("循环时间必须大于0");
        }
        if (StringUtils.isBlank(request.getRootPassword())) {
            return ApiResponse.error("Root密码不能为空");
        }

        // 2. 查询实例
        BootInstance instance = bootInstanceRepository.findById(Long.valueOf(request.getId()))
                .orElseThrow(() -> new RuntimeException("实例不存在"));

        // 3. 计算下次执行时间
        Timestamp currentTime = new Timestamp(System.currentTimeMillis());
        Timestamp oldNextExecutionTime = instance.getNextExecutionTime();

        // 如果循环时间变小了，需要特殊处理
        if (request.getLoopTime() < instance.getLoopTime()) {
            // 计算原定下次执行时间还有多久
            long remainSeconds = (oldNextExecutionTime.getTime() - currentTime.getTime()) / 1000;

            if (remainSeconds > request.getLoopTime()) {
                // 如果剩余时间比新的循环时间长，按新的循环时间计算
                int initialDelay = Math.max(request.getLoopTime(), scanInterval);
                instance.setNextExecutionTime(new Timestamp(currentTime.getTime() + initialDelay * 1000));
            } else {
                // 如果剩余时间比新的循环时间短，保持原有的下次执行时间
                instance.setNextExecutionTime(oldNextExecutionTime);
            }
        } else {
            // 如果循环时间变大或不变，保持原有的下次执行时间
            instance.setNextExecutionTime(oldNextExecutionTime);
        }

        // 4. 更新实例信息
        instance.setOcpu(request.getOcpu());
        instance.setMemory(request.getMemory());
        instance.setDisk(request.getDisk());
        instance.setLoopTime(request.getLoopTime());
        instance.setRootPassword(request.getRootPassword());
        instance.setUpdatedAt(LocalDateTime.now());
        instance.setDayGap(request.getDayGap());

        // 5. 保存更新
        try {
            bootInstanceRepository.saveAndFlush(instance);
            //更新实例的循环时间
            createInstanceTask.updateTaskInterval(instance.getBootId(), request.getLoopTime());
            return ApiResponse.success("success");
        } catch (Exception e) {
            log.error("更新实例配置失败", e);
            return ApiResponse.error("更新失败: " + e.getMessage());
        }
    }

    @Override
    public long countByStatus(int i) {
        return bootInstanceRepository.countByStatus(i);
    }

    @Override
    public Page<BootInstanceRes> getBootsByTenantId(String tenantId, int page, int size) {
        Pageable pageable = PageRequest.of(page, size);
        // 根据tenantId查询
        //Page<BootInstance> content = bootInstanceRepository.findByTenantId(Long.valueOf(tenantId), pageable);
        Page<BootInstance> content = bootInstanceRepository.findAllGroupedWithSumAddCount(Long.valueOf(tenantId), pageable);
        return doResult(content);
    }

    @Override
    public List<ImageInfoRes> querySystemImage(ImageInfoReq imageInfoReq) {
        try {
            return tenantRepository.findById(Long.valueOf(imageInfoReq.getTenantId()))
                    .map(tenant -> OciImageUtils.listImagesByShape(tenant, imageInfoReq.getShapeType()))
                    .orElse(Collections.emptyList());
        } catch (Exception e) {
            log.warn("query system image fail, reason: {}", e.getMessage());
            return Collections.emptyList();
        }
    }

    @Override
    public void batchInitFailCount() {
        bootInstanceRepository.batchInitFailCount();
    }

    @Override
    public Page<BootInstanceRes> findAllWithTenantInfo(String tenantId,Pageable pageable) {
        Long tenantIdLong = null;
        if (StringUtils.isNotBlank(tenantId)){
            tenantIdLong = Long.valueOf(tenantId);
        }
        Page<BootInstance> content = bootInstanceRepository.findAllWithTenantInfo(tenantIdLong, pageable);
        return doResult(content);
    }


    private Page<BootInstanceRes> doResult(Page<BootInstance> content){
        List<BootInstanceRes> bootInstanceRes = new ArrayList<>();

        if (CollectionUtil.isNotEmpty(content)) {
            for (BootInstance bootInstance : content) {
                BootInstanceRes bootInstanceUpdate = new BootInstanceRes();
                BeanUtils.copyProperties(bootInstance, bootInstanceUpdate);
                Optional<Tenant> optional = tenantRepository.findById(bootInstance.getTenantId());
                if (optional.isPresent()) {
                    Tenant tenant = optional.get();
                    Optional<CloudTenancy> byTenancyNameAndType = cloudTenancyRepository.findByTenancyNameAndType(tenant.getTenancy(), 1);
                    if (byTenancyNameAndType.isPresent()){
                        bootInstanceUpdate.setDefName(byTenancyNameAndType.get().getDefName());
                    }else {
                        bootInstanceUpdate.setDefName("未设置");
                    }
                    String tenancyName = tenant.getTenancyName();
                    if (StringUtils.isBlank(tenancyName)){
                        bootInstanceUpdate.setTenancyName(bootInstanceUpdate.getDefName());
                    }else{
                        bootInstanceUpdate.setTenancyName(tenancyName);
                    }
                    bootInstanceUpdate.setUserName(tenant.getUserName());
                    bootInstanceUpdate.setRegionName(RegionEnum.getNameSimple(tenant.getRegion()));
                }else{
                    bootInstanceUpdate.setDefName("未设置");
                    bootInstanceUpdate.setTenancyName("未设置");
                    bootInstanceUpdate.setUserName("未设置");
                    bootInstanceUpdate.setRegionName("未知");
                }
                bootInstanceUpdate.setAddCount(bootInstance.getAddCount() - bootInstance.getSuccessCount());
                bootInstanceUpdate.setRecordCount(bootInstance.getAddCount());
                bootInstanceUpdate.setCreateAtStr(bootInstance.getFormattedCreatedAt());
                //boolean b = bootInstanceRepository.existsRunningTaskByTenantId(bootInstance.getTenantId());
                long l = bootInstanceRepository.existsRunningTaskByTenantIdAndArchitecture(bootInstance.getTenantId(), bootInstance.getArchitecture());
                boolean b = l > 0;
                bootInstanceUpdate.setOpenBootFlag(b);
                bootInstanceUpdate.setExecutingCount(l);
                bootInstanceRes.add(bootInstanceUpdate);
            }
            return new PageImpl<>(bootInstanceRes, content.getPageable(), content.getTotalElements());
        } else {
            return new PageImpl<>(bootInstanceRes, content.getPageable(), content.getTotalElements());
        }
    }
}
