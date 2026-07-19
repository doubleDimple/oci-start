package com.doubledimple.ociserver.service.impl;

import cn.hutool.core.util.IdUtil;
import cn.hutool.core.util.RandomUtil;
import cn.hutool.json.JSONUtil;
import com.doubledimple.dao.entity.BootInstance;
import com.doubledimple.dao.entity.CloudTenancy;
import com.doubledimple.dao.entity.InstanceCloudNetWork;
import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.dao.entity.OtherBootInstance;
import com.doubledimple.dao.entity.RegisterDetail;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.entity.TenantEmailConfig;
import com.doubledimple.dao.entity.VpnProxyRecord;
import com.doubledimple.dao.entity.VpnProxyTenantBind;
import com.doubledimple.dao.repository.BootInstanceRepository;
import com.doubledimple.dao.repository.CloudTenancyRepository;
import com.doubledimple.dao.repository.OciComputerInfoRepository;
import com.doubledimple.dao.repository.OciMultipartUploadRecordRepository;
import com.doubledimple.dao.repository.OracleInstanceDetailRepository;
import com.doubledimple.dao.repository.OtherBootInstanceRepository;
import com.doubledimple.dao.repository.RegisterDetailRepository;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.dao.repository.VpnProxyRecordRepository;
import com.doubledimple.dao.repository.VpnProxyTenantBindRepository;
import com.doubledimple.ociai.chat.ChatAiService;
import com.doubledimple.ocicommon.enums.CloudTypeEnum;
import com.doubledimple.ocicommon.enums.RegionEnum;
import com.doubledimple.ocicommon.enums.oci.AccountTypeSubEnum;
import com.doubledimple.ocicommon.enums.oci.PlanTypeSubEnum;
import com.doubledimple.ocicommon.param.OpenRegionNotify;
import com.doubledimple.ocicommon.utils.FileUtils;
import com.doubledimple.ociserver.config.ProxyContext;
import com.doubledimple.ociserver.config.annotations.UseSocksProxy;
import com.doubledimple.ociserver.pojo.dto.OciAuditEventDto;
import com.doubledimple.ociserver.pojo.dto.OciPageResult;
import com.doubledimple.ociserver.pojo.dto.TenantTransferRequest;
import com.doubledimple.ociserver.pojo.enums.AccountTypeEnum;
import com.doubledimple.ociserver.pojo.enums.MessageEnum;
import com.doubledimple.ociserver.pojo.request.AuditLogRequest;
import com.doubledimple.ociserver.pojo.request.DeleteOciUserRequest;
import com.doubledimple.ociserver.pojo.request.ResetOciPassRequest;
import com.doubledimple.ociserver.pojo.response.PasswordPolicyDetail;
import com.doubledimple.ociserver.pojo.response.ResetOciPassResponse;
import com.doubledimple.ociserver.service.DbConfigService;
import com.doubledimple.ociserver.service.EmailService;
import com.doubledimple.ociserver.service.cloud.CloudInstanceServiceFactory;
import com.doubledimple.ociserver.utils.oracle.AuditLogUtils;
import com.doubledimple.ociserver.utils.oracle.OciClassLoader;
import com.doubledimple.ociserver.service.message.factory.MessageFactory;
import com.doubledimple.ociserver.service.oracle.OracleInstanceService;
import com.doubledimple.ociserver.service.oracle.sync.OciSyncQueueManager;
import com.doubledimple.ociserver.pojo.request.BootVolumeUpdateRequest;
import com.doubledimple.ociserver.pojo.request.TenancyDetail;
import com.doubledimple.ociserver.pojo.request.TenantDTO;
import com.doubledimple.ociserver.pojo.response.AccountCheckRes;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.pojo.response.BootVolumeRes;
import com.doubledimple.ociserver.pojo.response.OciGroupResp;
import com.doubledimple.ociserver.service.BootInstanceService;
import com.doubledimple.ociserver.service.RegisterDetailService;
import com.doubledimple.ociserver.service.TenantService;
import com.doubledimple.ociserver.config.task.CreateInstanceTaskV2;
import com.doubledimple.ociserver.utils.oracle.OciEmailUtils;
import com.doubledimple.ociserver.utils.oracle.OciGateWayUtils;
import com.doubledimple.ociserver.utils.oracle.OciUtils;
import com.doubledimple.ociserver.utils.oracle.SignOnPolicyUtils;
import com.doubledimple.ociserver.utils.oracle.region.OciRegionSubscriptionUtils;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.core.BlockstorageClient;
import com.oracle.bmc.core.VirtualNetworkClient;
import com.oracle.bmc.core.model.BootVolume;
import com.oracle.bmc.core.model.UpdateBootVolumeDetails;
import com.oracle.bmc.core.requests.ListBootVolumesRequest;
import com.oracle.bmc.core.requests.UpdateBootVolumeRequest;
import com.oracle.bmc.core.responses.ListBootVolumesResponse;
import com.oracle.bmc.core.responses.UpdateBootVolumeResponse;
import com.oracle.bmc.email.model.EmailDomain;
import com.oracle.bmc.identity.Identity;
import com.oracle.bmc.identity.IdentityClient;
import com.oracle.bmc.identity.model.RegionSubscription;
import com.oracle.bmc.identity.model.User;
import com.oracle.bmc.identity.requests.DeleteMfaTotpDeviceRequest;
import com.oracle.bmc.identity.requests.ListMfaTotpDevicesRequest;
import com.oracle.bmc.identity.requests.ListUsersRequest;
import com.oracle.bmc.identity.responses.ListMfaTotpDevicesResponse;
import com.oracle.bmc.identitydomains.model.PasswordPolicy;
import com.oracle.bmc.logging.LoggingManagementClient;
import com.oracle.bmc.ospgateway.model.Subscription;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.beans.BeanUtils;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Lazy;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.CollectionUtils;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import javax.annotation.Resource;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.atomic.AtomicReference;
import java.util.stream.Collectors;

import static com.doubledimple.ocicommon.template.MessageTemplate.MESSAGE_CONFIG_DEAD_ACCOUNT_TEMPLATE;
import static com.doubledimple.ocicommon.template.MessageTemplate.MESSAGE_CONFIG_SUCCESS_ACCOUNT_TEMPLATE;
import static com.doubledimple.ocicommon.template.MessageTemplate.MESSAGE_CONSOLE_PASSWORD_RESET_WITH_PASSWORD_TEMPLATE;
import static com.doubledimple.ocicommon.utils.DateTimeUtils.calculateDaysFromNow;
import static com.doubledimple.ocicommon.utils.FileUtils.deleteFile;
import static com.doubledimple.ociserver.utils.oracle.OciCliUtils.createVcnAndFlowLogs;
import static com.doubledimple.ociserver.utils.oracle.OciUtils.getProvider;

/**
 * @author doubleDimple
 * @date 2024:10:07日 21:01
 */
@Service
@Slf4j
public class TenantServiceImpl implements TenantService {

    @Value("${baseFile.filePath}")
    private String baseFile;

    @Resource
    private TenantRepository tenantRepository;

    @Resource
    private VpnProxyRecordRepository vpnProxyRecordRepository;

    @Resource
    private VpnProxyTenantBindRepository vpnProxyTenantBindRepository;

    @Resource
    private BootInstanceRepository bootInstanceRepository;

    @Resource
    MessageFactory messageFactory;

    @Resource
    OciClassLoader ociClassLoader;

    @Resource
    OracleInstanceService oracleInstanceService;

    @Resource
    OracleInstanceDetailRepository oracleInstanceDetailRepository;

    @Resource
    BootInstanceService bootInstanceService;

    /*@Resource
    TaskRepository taskRepository;*/

    @Resource
    CreateInstanceTaskV2 createInstanceTask;

    @Resource
    OciSyncQueueManager ociSyncQueueManager;

    @Resource
    RegisterDetailRepository registerDetailRepository;

    @Resource
    RegisterDetailService registerDetailService;

    @Resource
    OciComputerInfoRepository ociComputerInfoRepository;

    @Resource
    OtherBootInstanceRepository otherBootInstanceRepository;

    @Resource
    CloudTenancyRepository cloudTenancyRepository;

    @Resource
    CloudInstanceServiceFactory cloudInstanceServiceFactory;

    @Resource
    EmailService emailService;

    @Resource
    OciMultipartUploadRecordRepository ociMultipartUploadRecordRepository;

    @Resource
    AuditLogUtils auditLogUtils;

    @Resource
    OciEmailUtils ociEmailUtils;

    @Resource
    ChatAiService chatAiService;

    @Resource
    @Lazy
    private TenantService self;

    @Resource
    @Lazy
    private DbConfigService dbConfigService;

    @Override
    @Transactional
    public Page<Tenant> getAllTenants(Integer cloudType, int page, int size) {
        Pageable pageable = PageRequest.of(page, size,Sort.by(
                Sort.Order.desc("createdAt"),
                Sort.Order.asc("region")
        ));

        // 获取父记录
        Page<Tenant> parentTenants = tenantRepository.findByParenIdIsNullOrParenIdAndCloudType( 0L,cloudType, pageable);

        if (parentTenants != null && !parentTenants.getContent().isEmpty()) {
            List<Tenant> modifiedContent = new ArrayList<>();

            // 处理每个父记录
            for (Tenant parent : parentTenants.getContent()) {
                Optional<CloudTenancy> byTenancyNameAndCloudType = cloudTenancyRepository.findByTenancyNameAndCloudTypeAndType(parent.getTenancy(), cloudType,1);
                if (byTenancyNameAndCloudType.isPresent()){
                    CloudTenancy cloudTenancy = byTenancyNameAndCloudType.get();
                    String cost = cloudTenancy.getAccountCost() == null ? "0" : cloudTenancy.getAccountCost();
                    parent.setDefName(cloudTenancy.getDefName());
                    parent.setAccountCost(cost);
                }else {
                    parent.setDefName(parent.getUserName());
                    parent.setAccountCost("0");
                }
                // 设置区域名称
                parent.setIdStr(parent.getId().toString());
                String regionName = RegionEnum.getNameByCode(parent.getRegion());
                parent.setRegion(regionName);
                Optional<RegisterDetail> byTenantId = registerDetailRepository.findByTenantId(parent.getTenantId());
                if (byTenantId.isPresent()){
                    RegisterDetail registerDetail = byTenantId.get();
                    parent.setRegisterDetail(registerDetail);
                    Subscription.AccountType accountType = registerDetail.getAccountType();
                    Subscription.PlanType planType = registerDetail.getPlanType();
                    String accountTypeName = AccountTypeSubEnum.getByCode(accountType.getValue()) + PlanTypeSubEnum.getByCode(planType.getValue());
                    if (StringUtils.isNotBlank(accountTypeName)){
                        parent.setAccountTypeName(accountTypeName);
                    }else {
                        parent.setAccountTypeName("未知");
                    }
                    //计算账号天数
                    String activeDays = calculateDaysFromNow(registerDetail.getRegisterTime());
                    parent.setActiveDays(activeDays);
                }else {
                    parent.setAccountTypeName("未知");
                }
                boolean contains = RegionEnum.getSupportAiRegion().contains(RegionEnum.getCodeByName(parent.getRegion()));
                if (contains){
                    parent.setSupportAI(1);
                }
                AtomicReference<Boolean> openInsFlag = new AtomicReference<>(false);
                if (openInsFlag.get().equals(Boolean.FALSE)){
                    Boolean openInsFlagChild = bootInstanceRepository.existsRunningTaskByTenantId(parent.getId());
                    if (openInsFlagChild){
                        openInsFlag.set(true);
                    }
                }
                // 获取并处理子记录
                //List<Tenant> children = tenantRepository.findByParenId(parent.getId());
                List<Tenant> children = this.regionList(parent.getId());
                //final List<Tenant> collect = children.stream().filter(child -> !child.getIsHomeRegion()).collect(Collectors.toList());
                children.removeIf(child -> child.getId().equals(parent.getId()));
                Tenant parentClone = new Tenant();
                BeanUtils.copyProperties(parent, parentClone);
                parentClone.setChildren(null);
                parentClone.setRegion(parent.getRegion());
                children.add(0, parentClone);
                if (!children.isEmpty()) {
                    children.forEach(child -> {
                        child.setRegion(RegionEnum.getNameByCode(child.getRegion()));
                        child.setIdStr(child.getId().toString());
                        boolean childContains = RegionEnum.getSupportAiRegion().contains(RegionEnum.getCodeByName(child.getRegion()));
                        if (childContains){
                            parent.setSupportAI(1);
                        }
                        child.setChildren(null);
                        child.setHasChildren(false);
                        if (openInsFlag.get().equals(Boolean.FALSE)){
                            boolean b = bootInstanceRepository.existsRunningTaskByTenantId(child.getId());
                            openInsFlag.set(b);
                        }
                    });
                    parent.setChildren(children);
                    parent.setHasChildren(true);
                } else {
                    boolean b = bootInstanceRepository.existsRunningTaskByTenantId(parent.getId());
                    openInsFlag.set(b);
                    parent.setHasChildren(false);
                }
                parent.setOpenBootFlag(openInsFlag.get());
                modifiedContent.add(parent);
            }

            fillProxyBoundFlags(modifiedContent);
            return new PageImpl<>(modifiedContent, parentTenants.getPageable(), parentTenants.getTotalElements());
        }

        return parentTenants;
    }

    /**
     * 批量标记是否已绑定专属代理 / 是否强制代理（列表护盾）。
     * 绑定记在父租户上时，子区域也算已绑定（继承）。
     * <ul>
     *   <li>绿：已绑定且非强制</li>
     *   <li>橙：已绑定且强制代理</li>
     *   <li>灰：未绑定</li>
     * </ul>
     */
    private void fillProxyBoundFlags(List<Tenant> tenants) {
        if (tenants == null || tenants.isEmpty()) {
            return;
        }
        try {
            // 租户 → 是否强制（true=强制，false=已绑非强制）
            java.util.Map<Long, Boolean> forceByTenant = new java.util.HashMap<>();

            // 1) 新绑定表
            try {
                List<VpnProxyTenantBind> binds = vpnProxyTenantBindRepository.findAll();
                if (binds != null && !binds.isEmpty()) {
                    java.util.Set<Long> proxyIds = new java.util.HashSet<>();
                    for (VpnProxyTenantBind b : binds) {
                        if (b != null && b.getProxyId() != null) {
                            proxyIds.add(b.getProxyId());
                        }
                    }
                    java.util.Map<Long, VpnProxyRecord> proxyMap = new java.util.HashMap<>();
                    if (!proxyIds.isEmpty()) {
                        for (VpnProxyRecord r : vpnProxyRecordRepository.findAllById(proxyIds)) {
                            if (r != null && r.getId() != null) {
                                proxyMap.put(r.getId(), r);
                            }
                        }
                    }
                    for (VpnProxyTenantBind b : binds) {
                        if (b == null || b.getTenantId() == null || b.getProxyId() == null) {
                            continue;
                        }
                        VpnProxyRecord r = proxyMap.get(b.getProxyId());
                        boolean force = r != null && r.getForceProxy() != null && r.getForceProxy() == 1;
                        Boolean prev = forceByTenant.get(b.getTenantId());
                        forceByTenant.put(b.getTenantId(), (prev != null && prev) || force);
                    }
                }
            } catch (Exception ignore) {
                // bind 表尚未创建时忽略，走旧列
            }

            // 2) 兼容旧 tenant_id 列
            List<VpnProxyRecord> boundRecords = vpnProxyRecordRepository.findAllBoundRecords();
            if (boundRecords != null) {
                for (VpnProxyRecord r : boundRecords) {
                    if (r == null || r.getTenantId() == null) {
                        continue;
                    }
                    // 若已从 bind 表写入则合并强制标记
                    boolean force = r.getForceProxy() != null && r.getForceProxy() == 1;
                    Boolean prev = forceByTenant.get(r.getTenantId());
                    forceByTenant.put(r.getTenantId(), (prev != null && prev) || force);
                }
            }
            for (Tenant t : tenants) {
                if (t == null || t.getId() == null) {
                    continue;
                }
                Long bindKey = t.getId();
                boolean bound = forceByTenant.containsKey(bindKey);
                boolean force = bound && Boolean.TRUE.equals(forceByTenant.get(bindKey));
                if (!bound) {
                    Long parenId = t.getParenId();
                    if (parenId != null && parenId > 0L && forceByTenant.containsKey(parenId)) {
                        bindKey = parenId;
                        bound = true;
                        force = Boolean.TRUE.equals(forceByTenant.get(parenId));
                    }
                }
                t.setProxyBound(bound);
                t.setProxyForce(bound && force);
            }
        } catch (Exception e) {
            log.debug("填充代理绑定标识失败: {}", e.getMessage());
        }
    }

    @Override
    @Transactional
    public Page<Tenant> getAllTenantsByParentId(Long Id,Integer cloudType, int page, int size) {
        Pageable pageable = PageRequest.of(page, size,Sort.by(
                Sort.Order.asc("region"),
                Sort.Order.desc("createdAt")
        ));
        Optional<Tenant> byId = tenantRepository.findById(Id);
        if (!byId.isPresent()){
            return null;
        }
        Tenant parent = byId.get();
        List<Tenant> modifiedContent = new ArrayList<>();

        // 处理每个父记录
        Optional<CloudTenancy> byTenancyNameAndCloudType = cloudTenancyRepository.findByTenancyNameAndCloudTypeAndType(parent.getTenancy(), cloudType,1);
        if (byTenancyNameAndCloudType.isPresent()){
            parent.setDefName(byTenancyNameAndCloudType.get().getDefName());
        }else {
            parent.setDefName(parent.getUserName());
        }
        // 设置区域名称
        parent.setIdStr(parent.getId().toString());
        String regionName = RegionEnum.getNameByCode(parent.getRegion());
        parent.setRegion(regionName);
        Optional<RegisterDetail> byTenantId = registerDetailRepository.findByTenantId(parent.getTenantId());
        if (byTenantId.isPresent()){
            RegisterDetail registerDetail = byTenantId.get();
            parent.setRegisterDetail(registerDetail);
            Subscription.AccountType accountType = registerDetail.getAccountType();
            Subscription.PlanType planType = registerDetail.getPlanType();
            String accountTypeName = AccountTypeSubEnum.getByCode(accountType.getValue()) + PlanTypeSubEnum.getByCode(planType.getValue());
            if (StringUtils.isNotBlank(accountTypeName)){
                parent.setAccountTypeName(accountTypeName);
            }else {
                parent.setAccountTypeName("未知");
            }
        }else {
            parent.setAccountTypeName("未知");
        }
        boolean contains = RegionEnum.getSupportAiRegion().contains(RegionEnum.getCodeByName(parent.getRegion()));
        if (contains){
            parent.setSupportAI(1);
        }
        AtomicReference<Boolean> openInsFlag = new AtomicReference<>(false);
        if (openInsFlag.get().equals(Boolean.FALSE)){
            Boolean openInsFlagChild = bootInstanceRepository.existsRunningTaskByTenantId(parent.getId());
            if (openInsFlagChild){
                openInsFlag.set(true);
            }
        }
        // 获取并处理子记录
        //List<Tenant> children = tenantRepository.findByParenId(parent.getId());
        List<Tenant> children = this.regionList(parent.getId());
        children.removeIf(child -> child.getId().equals(parent.getId()));
        if (!children.isEmpty()) {
            children.forEach(child -> {
                child.setRegion(RegionEnum.getNameByCode(child.getRegion()));
                child.setIdStr(child.getId().toString());
                boolean childContains = RegionEnum.getSupportAiRegion().contains(RegionEnum.getCodeByName(child.getRegion()));
                if (childContains){
                    parent.setSupportAI(1);
                }
                child.setChildren(null);
            });
            parent.setChildren(children);
            parent.setHasChildren(true);
        } else {
            boolean b = bootInstanceRepository.existsRunningTaskByTenantId(parent.getId());
            openInsFlag.set(b);
            parent.setHasChildren(false);
        }
        parent.setOpenBootFlag(openInsFlag.get());
        modifiedContent.add(parent);

        return new PageImpl<>(modifiedContent, pageable, 1);
    }

    @Transactional(rollbackFor = Exception.class)
    @Override
    public void saveTenant(Tenant tenant, MultipartFile keyFile) throws IOException {
        int cloudType = tenant.getCloudType();
        if (keyFile != null && !keyFile.isEmpty()) {
            String fileName = LocalDateTime.now() + "_" + keyFile.getOriginalFilename();
            FileUtils.checkFile(baseFile);
            Path filePath = Paths.get(baseFile, fileName);
            Files.createDirectories(filePath.getParent());
            Files.write(filePath, keyFile.getBytes());
            tenant.setKeyFile(filePath.toString());
        }
        String shortCode = RandomUtil.randomString(6);
        String userName = RegionEnum.getRegionCode(tenant.getRegion()) + "_" + shortCode;
        List<RegionSubscription> regionSubscriptions = null;
        TenancyDetail tenancyDetail = null;
        Subscription subscription = null;
        String tenancyName = null;
        String description = null;
        if (CloudTypeEnum.ORACLE_CLOUD.getType() == cloudType){
            tenancyDetail = ociClassLoader.loadManyRegions(tenant);
            subscription = OciGateWayUtils.getAccountTypeInfo(tenant);
            tenancyName = tenancyDetail.getTenancyName();
            if (tenancyName == null)tenancyName = tenant.getUserName();
            description = tenancyDetail.getDescription();
            if (description == null)description = StringUtils.EMPTY;
            regionSubscriptions = tenancyDetail.getRegionSubscriptions();
        }else if (CloudTypeEnum.GOOGLE_CLOUD.getType() == cloudType){
            tenancyName = tenant.getUserName();
            description = StringUtils.EMPTY;
            tenancyDetail = new TenancyDetail();
            tenancyDetail.setAccountTypeEnum(AccountTypeEnum.FREE_ACCOUNT);
            tenant.setRegion(RegionEnum.GCP_REGION.getCode());
        }
        List<Tenant> tenants = new ArrayList<>();
        long snowflakeNextId = IdUtil.getSnowflakeNextId();
        if (regionSubscriptions == null){
            Tenant tenantAdd = new Tenant();
            BeanUtils.copyProperties(tenant, tenantAdd);
            List<Tenant> tenantList = tenantRepository.queryByUserName(tenantAdd.getUserName());
            if (tenantList.size() > 0){
                userName = RegionEnum.getRegionCode(tenant.getRegion()) + "_" + RandomUtil.randomString(6);
            }else{
                userName = tenantAdd.getUserName();
            }
            long parentId = 0L;
            log.debug("当前区域:{}为主区域", tenant.getRegion());
            tenantAdd.setId(snowflakeNextId);
            tenantAdd.setParenId(parentId);
            AccountTypeEnum accountTypeEnum = tenancyDetail.getAccountTypeEnum();
            if (null != accountTypeEnum) {
                tenantAdd.setAccountType(tenancyDetail.getAccountTypeEnum().getType());
            } else {
                tenantAdd.setAccountType(AccountTypeEnum.UN_KNOW_ACCOUNT.getType());
            }
            //只有是主区域的时候保存注册信息
            if (subscription != null) {
                registerDetailService.saveRegisterDetail(snowflakeNextId, tenant.getTenantId(), subscription);
            }
            tenantAdd.setUserName(userName);
            tenantAdd.setRegion(RegionEnum.getRegionCode(tenant.getRegion()));
            tenantAdd.setIsHomeRegion(true);
            tenantAdd.setTenancyName(tenancyName);
            tenantAdd.setTenancyDes(description);
            tenants.add(tenantAdd);
        }else{
            for (RegionSubscription regionSubscription : regionSubscriptions) {
                doExecuteTenants(tenants,tenant,regionSubscription,snowflakeNextId,subscription,tenancyDetail,tenancyName,description);
            }
        }

        log.debug("保存租户的信息是:{}", JSONUtil.toJsonStr(tenants));
        tenantRepository.saveAll(tenants);
    }

    @Transactional(rollbackFor = Exception.class)
    @Override
    public List<Tenant> saveTenantInner(Tenant tenant) throws IOException {
        int cloudType = tenant.getCloudType();
        String userName = "";
        List<RegionSubscription> regionSubscriptions = null;
        TenancyDetail tenancyDetail = null;
        Subscription subscription = null;
        String tenancyName = null;
        String description = null;
        if (CloudTypeEnum.ORACLE_CLOUD.getType() == cloudType){
            tenancyDetail = ociClassLoader.loadManyRegionsInner(tenant);
            subscription = OciGateWayUtils.getAccountTypeInfo(tenant);
            tenancyName = tenancyDetail.getTenancyName();
            if (tenancyName == null)tenancyName = tenant.getUserName();
            description = tenancyDetail.getDescription();
            if (description == null)description = StringUtils.EMPTY;
            regionSubscriptions = tenancyDetail.getRegionSubscriptions();
        }else if (CloudTypeEnum.GOOGLE_CLOUD.getType() == cloudType){
            tenancyName = tenant.getUserName();
            description = StringUtils.EMPTY;
            tenancyDetail = new TenancyDetail();
            tenancyDetail.setAccountTypeEnum(AccountTypeEnum.FREE_ACCOUNT);
            tenant.setRegion(RegionEnum.GCP_REGION.getCode());
        }
        List<Tenant> tenants = new ArrayList<>();
        long snowflakeNextId = IdUtil.getSnowflakeNextId();
        if (regionSubscriptions == null){
            Tenant tenantAdd = new Tenant();
            BeanUtils.copyProperties(tenant, tenantAdd);
            List<Tenant> tenantList = tenantRepository.queryByUserName(tenantAdd.getUserName());
            if (tenantList.size() > 0){
                //重复
                userName = tenantAdd.getUserName() +"_" +RegionEnum.getRegionCode(tenant.getRegion()) +"_" + System.currentTimeMillis();
            }else{
                userName = tenantAdd.getUserName();
            }
            long parentId = 0L;
            log.debug("当前区域:{}为主区域", tenant.getRegion());
            tenantAdd.setId(snowflakeNextId);
            tenantAdd.setParenId(parentId);
            AccountTypeEnum accountTypeEnum = tenancyDetail.getAccountTypeEnum();
            if (null != accountTypeEnum) {
                tenantAdd.setAccountType(tenancyDetail.getAccountTypeEnum().getType());
            } else {
                tenantAdd.setAccountType(AccountTypeEnum.UN_KNOW_ACCOUNT.getType());
            }
            //只有是主区域的时候保存注册信息
            if (subscription != null) {
                registerDetailService.saveRegisterDetail(snowflakeNextId, tenant.getTenantId(), subscription);
            }
            tenantAdd.setUserName(userName);
            tenantAdd.setRegion(RegionEnum.getRegionCode(tenant.getRegion()));
            tenantAdd.setIsHomeRegion(true);
            tenantAdd.setTenancyName(tenancyName);
            tenantAdd.setTenancyDes(description);
            tenants.add(tenantAdd);
        }else{
            for (RegionSubscription regionSubscription : regionSubscriptions) {
                doExecuteTenants(tenants,tenant,regionSubscription,snowflakeNextId,subscription,tenancyDetail,tenancyName,description);
            }
        }

        log.debug("保存租户的信息是:{}", JSONUtil.toJsonStr(tenants));
        tenantRepository.saveAll(tenants);
        return tenants;
    }

    private void doExecuteTenants(List<Tenant> tenants,Tenant tenant,RegionSubscription regionSubscription,Long snowflakeNextId,Subscription subscription,TenancyDetail tenancyDetail,String tenancyName,String description) {
        Tenant tenantAdd = new Tenant();
        BeanUtils.copyProperties(tenant, tenantAdd);
        List<Tenant> tenantList = tenantRepository.queryByUserName(tenantAdd.getUserName());
        String userName = "";
        if (tenantList.size() > 0){
            //重复
            userName = tenantAdd.getUserName() +"_" +regionSubscription.getRegionName() +"_" + System.currentTimeMillis();
        }else{
            userName = tenantAdd.getUserName();
        }
        long parentId = 0L;
        Boolean isHomeRegion = regionSubscription.getIsHomeRegion();
        if (isHomeRegion){
            log.debug("当前区域:{}为主区域", regionSubscription.getRegionName() );
            tenantAdd.setId(snowflakeNextId);
            tenantAdd.setParenId(parentId);
            AccountTypeEnum accountTypeEnum = tenancyDetail.getAccountTypeEnum();
            if (null != accountTypeEnum){
                tenantAdd.setAccountType(tenancyDetail.getAccountTypeEnum().getType());
            }else {
                tenantAdd.setAccountType(AccountTypeEnum.UN_KNOW_ACCOUNT.getType());
            }
            //只有是主区域的时候保存注册信息
            if (subscription != null){
                registerDetailService.saveRegisterDetail(snowflakeNextId, tenant.getTenantId(), subscription);
            }
        }else{
            log.info("当前区域:{}为附区域", regionSubscription.getRegionName());
            tenantAdd.setId(IdUtil.getSnowflakeNextId());
            tenantAdd.setParenId(snowflakeNextId);
        }

        //保存网络信息
        /*List<InstanceCloudNetWork> instanceCloudNetWorkList = doCreateCloudNetWork(tenant);
        oracleCloudNetworkService.saveBatch(instanceCloudNetWorkList);*/

        tenantAdd.setUserName(userName);
        tenantAdd.setRegion(regionSubscription.getRegionName());
        tenantAdd.setIsHomeRegion(regionSubscription.getIsHomeRegion());
        tenantAdd.setTenancyName(tenancyName);
        tenantAdd.setTenancyDes(description);
        tenants.add(tenantAdd);
    }

    /**
    * 获取租户区域下的网络信息
    */
    @Override
    public List<InstanceCloudNetWork> doCreateCloudNetWork(Tenant tenant) {
        List<InstanceCloudNetWork> instanceCloudNetWorkList = new ArrayList<>();
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        try (VirtualNetworkClient virtualNetworkClient = VirtualNetworkClient.builder().build(provider);
             LoggingManagementClient loggingManagementClient = LoggingManagementClient.builder().build(provider);) {
             instanceCloudNetWorkList = createVcnAndFlowLogs(tenant.getTenantId(), tenant.getRegion(), tenant.getCloudType() , virtualNetworkClient, loggingManagementClient, provider.getTenantId(), 1);
        } catch (Exception e) {
            log.error("创建vcn和日志组失败:", e);
        }
        return instanceCloudNetWorkList;
    }

    @Transactional
    @Override
    public List<Tenant> updateTenancyDetail(String tenantId) {
        List<Tenant> tenants = new ArrayList<>();
        Tenant tenant = getById(Long.valueOf(tenantId));
        if (tenant != null){
            try {
                self.deleteApi(Long.valueOf(tenantId),Boolean.FALSE);
                Path path = Paths.get(tenant.getKeyFile()).toAbsolutePath().normalize();
                tenant.setTmpKeyFile(path.toAbsolutePath().toString());
                tenants = self.saveTenantInner(tenant);
            } catch (IOException e) {
                throw new RuntimeException(e);
            }
        }
        return tenants;
    }

    /**
    * 获取已经订阅的区域列表
    */
    @Override
    public List<RegionSubscription> regionSub(long tenantId) {
        Tenant tenant = getById(tenantId);
        List<RegionSubscription> subscribedRegions = OciRegionSubscriptionUtils.getSubscribedRegions(tenant);
        return subscribedRegions;
    }

    @Override
    @Transactional
    public boolean updateCustomName(Tenant tenant, String defName) {
        Optional<CloudTenancy> byTenancyName = cloudTenancyRepository.findByTenancyNameAndCloudTypeAndType(tenant.getTenancy(),tenant.getCloudType(),1);
        if (byTenancyName.isPresent()){
            CloudTenancy cloudTenancy = byTenancyName.get();
            cloudTenancy.setTenancyName(tenant.getTenancy());
            cloudTenancy.setDefName(defName);
            cloudTenancy.setCloudType(tenant.getCloudType());
            cloudTenancy.setType(1);
            cloudTenancyRepository.save(cloudTenancy);
        }else{
            CloudTenancy cloudTenancy = new CloudTenancy();
            cloudTenancy.setTenancyName(tenant.getTenancy());
            cloudTenancy.setCloudType(tenant.getCloudType());
            cloudTenancy.setDefName(defName);
            cloudTenancy.setType(1);
            cloudTenancyRepository.save(cloudTenancy);
        }
        return true;
    }

    @Override
    public boolean updateAccountCost(Tenant tenant, String newCost) {
        Optional<CloudTenancy> byTenancyName = cloudTenancyRepository.findByTenancyNameAndCloudTypeAndType(tenant.getTenancy(),tenant.getCloudType(),1);
        if (byTenancyName.isPresent()){
            CloudTenancy cloudTenancy = byTenancyName.get();
            cloudTenancy.setTenancyName(tenant.getTenancy());
            cloudTenancy.setAccountCost(newCost);
            cloudTenancy.setCloudType(tenant.getCloudType());
            cloudTenancy.setType(1);
            cloudTenancyRepository.save(cloudTenancy);
        }else{
            CloudTenancy cloudTenancy = new CloudTenancy();
            cloudTenancy.setTenancyName(tenant.getTenancy());
            cloudTenancy.setCloudType(tenant.getCloudType());
            cloudTenancy.setAccountCost(newCost);
            cloudTenancy.setType(1);
            cloudTenancyRepository.save(cloudTenancy);
        }
        return true;
    }

    @Override
    public Page<Tenant> findParentTenant(int cloudType, int page, int size) {
        Pageable pageable = PageRequest.of(page, size,Sort.by(
                Sort.Order.asc("region"),
                Sort.Order.desc("createdAt")
        ));

        // 获取父记录
        return tenantRepository.findParentTenant( cloudType, pageable);
    }


    /**
    * @Description: updateUserPasswordPolicy
    * @Param: [java.lang.String, boolean, java.lang.Integer]
    * @return: void
     * enablePasswordExpiry
     * true 表示启用强制修改密码
     * false 表示禁用强制修改密码
    * @Author: doubleDimple
    * @Date: 8/24/25 3:56 PM
    */
    @Override
    public Boolean updateUserPasswordPolicy(String tenantId, boolean enablePasswordExpiry, Integer expiryDays) {
        if (enablePasswordExpiry) {
            int days = expiryDays == null ? 120 : expiryDays;
            if (days < 0 || days > 365) {
                throw new IllegalArgumentException("过期天数必须在0-365之间");
            }
            expiryDays = days;
        }
        Tenant tenant = tenantRepository.findById(Long.valueOf(tenantId)).get();
        Boolean result = Boolean.TRUE;
        if (enablePasswordExpiry){
            result =  OciUtils.enablePasswordExpirationWithAutoDomain(tenant, expiryDays);
        }else{
            result = OciUtils.disablePasswordExpirationWithAutoDomain(tenant);
        }
        return result;
    }

    @Override
    public List<PasswordPolicyDetail> getPasspolicy(String tenantId) {
        Tenant tenant = tenantRepository.findById(Long.valueOf(tenantId)).get();
        List<PasswordPolicyDetail> result = new ArrayList<>();
        List<PasswordPolicy> currentPasswordPolicy = OciUtils.getCurrentPasswordPolicy(tenant);
        if (!CollectionUtils.isEmpty(currentPasswordPolicy)){
            for (PasswordPolicy passwordPolicy : currentPasswordPolicy) {
                PasswordPolicy.PasswordStrength passwordStrength = passwordPolicy.getPasswordStrength();
                if (!passwordStrength.equals(PasswordPolicy.PasswordStrength.Custom)){
                    log.debug("{}当前策略不支持修改",passwordPolicy.getName());
                    continue;
                }
                PasswordPolicyDetail passwordPolicyDetail = new PasswordPolicyDetail();
                passwordPolicyDetail.setName(passwordPolicy.getName());
                Integer passwordExpiresAfter = passwordPolicy.getPasswordExpiresAfter();
                if (passwordExpiresAfter != null && passwordExpiresAfter > 0){
                    passwordPolicyDetail.setEnablePasswordExpiry(true);
                    passwordPolicyDetail.setExpiryDays(passwordExpiresAfter);
                }else {
                    passwordPolicyDetail.setEnablePasswordExpiry(false);
                    passwordPolicyDetail.setExpiryDays(0);
                }
                result.add(passwordPolicyDetail);
            }
        }
        return result;
    }

    @Override
    public List<Tenant> querySupportAiRecords(int cloudType) {
        List<Tenant> all = tenantRepository.findAll();
        List<Tenant> newList = new ArrayList<>();
        if (!CollectionUtils.isEmpty( all)){
            for (Tenant tenant : all) {
                if (tenant.getCloudType() == cloudType){
                    boolean contains = RegionEnum.getSupportAiRegion().contains(RegionEnum.getCodeByName(tenant.getRegion()));
                    if (contains){
                        newList.add(tenant);
                    }
                }
            }
        }
        return newList;
    }

    @Override
    public ApiResponse resetPassword(ResetOciPassRequest request) {
        String userId = request.getUserId();
        try {
            Tenant tenant = tenantRepository.findById(Long.valueOf(request.getTenantId())).get();
            ResetOciPassResponse resetOciPassResponse = SignOnPolicyUtils.resetPass(tenant,userId);
            resetOciPassResponse.setLoginUser(request.getUserName());
            if (StringUtils.isNotBlank(resetOciPassResponse.getTemporaryPassword())) {
                // 重置成功，发送通知
                messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplate(String.
                        format(MESSAGE_CONSOLE_PASSWORD_RESET_WITH_PASSWORD_TEMPLATE,
                                tenant.getUserName(),
                                request.getUserName(),
                                resetOciPassResponse.getTemporaryPassword(),
                                resetOciPassResponse.getResetTime()
                        ));
                return ApiResponse.success(resetOciPassResponse);

            } else if ("IDENTITY_DOMAIN_USER".equals(resetOciPassResponse.getResetTime())) {
                return ApiResponse.error("该用户属于身份域，请在OCI控制台的身份域中手动重置密码");

            } else if ("PERMISSION_DENIED".equals(resetOciPassResponse.getResetTime())) {
                return ApiResponse.error("权限不足，无法重置该用户的密码");

            } else {
                return ApiResponse.error("密码重置失败，请检查用户状态");
            }
        } catch (Exception e) {
            log.error("重置密码失败: {}", e.getMessage(), e);
            return ApiResponse.error("密码重置失败：" + e.getMessage());
        }
    }

    @Override
    public ApiResponse enableEmailService(Map<String, Object> request) {
        try {
            Object emailDomain = request.get("emailDomain");
            if (emailDomain == null) {
                return ApiResponse.error("邮件域名不能为空");
            }
            String emailDomainName = emailDomain.toString();
            // 参数验证
            Object tenantIdObj = request.get("tenantId");
            if (tenantIdObj == null) {
                return ApiResponse.error("租户ID不能为空");
            }

            Long tenantId;
            try {
                tenantId = Long.valueOf(tenantIdObj.toString());
            } catch (NumberFormatException e) {
                return ApiResponse.error("租户ID格式错误");
            }
            Tenant tenant = getById(tenantId);
            if (tenant == null) {
                return ApiResponse.error("租户不存在");
            }

            // 检查是否已经启用过邮件服务
            if (tenant.getEmailEnable() == 1) {
                EmailDomain emailDomainByName = ociEmailUtils.findEmailDomainByName(tenant, emailDomainName);
                if (emailDomainByName != null){
                    log.warn("当前租户已经启用过邮件服务,且输入的邮箱域名和当前租户的邮箱域名一致");
                    TenantEmailConfig tenantEmailConfig = emailService.getTenantEmailConfigByName(emailDomainName);
                    if (tenantEmailConfig != null){
                        //查询租户id是否存在
                        Optional<Tenant> byId = tenantRepository.findById(tenantEmailConfig.getTenantId());
                        if (!byId.isPresent()){
                            //需要重新绑定
                            emailService.update(tenant,tenantEmailConfig);
                            log.info("租户[{}]邮件服务重新绑定成功", tenantId);
                            return ApiResponse.success();
                        }
                    }
                }

            }

            ApiResponse apiResponse = emailService.enableEmailForTenant(tenant, emailDomainName, tenantId);
            if (null == apiResponse || !apiResponse.isSuccess()){
                tenant.setEmailEnable(0);
            }else{
                // 更新租户邮件启用状态
                tenant.setEmailEnable(1);
            }
            tenantRepository.save(tenant);
            log.info("租户[{}]邮件服务启用成功", tenantId);
            return ApiResponse.success();

        } catch (Exception e) {
            log.error("启用邮件服务时发生异常", e);
            return ApiResponse.error("启用邮件服务失败: " + e.getMessage());
        }
    }

    @Override
    public ApiResponse getEmailServiceStatus(Long tenantId) {
        return null;
    }

    @Override
    public ApiResponse disableEmailService(Map<String, Object> request) {
        return null;
    }

    @Override
    public ApiResponse testEmailService(Map<String, Object> request) {
        return null;
    }

    @Override
    public ApiResponse deleteUser(DeleteOciUserRequest request) {
        String userId = request.getUserId();
        try {
            Tenant tenant = tenantRepository.findById(Long.valueOf(request.getTenantId())).get();
            SignOnPolicyUtils.deleteUser(tenant,userId);
            return ApiResponse.success("删除用户成功");
        } catch (Exception e) {
            log.error("重置密码失败: {}", e.getMessage(), e);
            return ApiResponse.error("密码重置失败：" + e.getMessage());
        }
    }

    @Override
    public SseEmitter streamAccountCheckProgress() {
        // 不设置超时，确保长连接持续存在
        SseEmitter emitter = new SseEmitter(0L);

        new Thread(() -> {
            try {
                // 1. 获取租户信息
                Page<Tenant> allTenants = findParentTenant(1, 0, 1000);

                if (allTenants == null) {
                    emitter.send(SseEmitter.event().name("error").data("没有获取到租户信息"));
                    emitter.complete();
                    return;
                }

                List<Tenant> all = allTenants.getContent();
                int totalAccounts = all.size();
                int activeAccounts = 0;
                int inactiveAccounts = 0;
                List<String> inactiveAccountNames = new ArrayList<>();

                // 2. 推送检测开始信息
                Map<String, Object> startData = new HashMap<>();
                startData.put("message", "开始检测，共 " + totalAccounts + " 个账号...");
                startData.put("total", totalAccounts);
                emitter.send(SseEmitter.event().name("start").data(startData));


                // 3. 遍历检测
                List<Long> noActiveIds = new ArrayList<>();
                if (!CollectionUtils.isEmpty(all)) {
                    for (int i = 0; i < all.size(); i++) {
                        Tenant tenant = all.get(i);
                        String username = tenant.getUserName();
                        try {
                            ResponseEntity<?> responseEntity = oracleInstanceService.checkAccountStatus(tenant.getId());
                            boolean isActive = isStatusSuccess(responseEntity);

                            if (isActive) {
                                activeAccounts++;
                                emitter.send(SseEmitter.event()
                                        .name("progress")
                                        .data(String.format("✅ [%d/%d] %s 正常", i + 1, totalAccounts, username)));
                            } else {
                                noActiveIds.add(tenant.getId());
                                inactiveAccounts++;
                                inactiveAccountNames.add(username);
                                emitter.send(SseEmitter.event()
                                        .name("progress")
                                        .data(String.format("❌ [%d/%d] %s 异常", i + 1, totalAccounts, username)));
                            }

                            // 轻微延迟，避免过快推送导致前端无法及时显示
                            Thread.sleep(300);

                        } catch (Exception ex) {
                            log.warn("检测账号失败 {}: {}", username, ex.getMessage());
                            emitter.send(SseEmitter.event()
                                    .name("progress")
                                    .data(String.format("⚠️ [%d/%d] %s 检测失败：%s", i + 1, totalAccounts, username, ex.getMessage())));
                        }
                    }
                }

                // 4. 推送最终结果
                AccountCheckRes result = new AccountCheckRes(totalAccounts, activeAccounts, inactiveAccounts, inactiveAccountNames);
                emitter.send(SseEmitter.event().name("complete").data(result));

                // 5. 发送 Telegram 消息
                try {
                    //处理失效账号
                    if (!noActiveIds.isEmpty()) {
                        tenantRepository.batchUpdateStatusToInactive(noActiveIds);
                    }

                    if (!inactiveAccountNames.isEmpty()) {
                        messageFactory.getType(MessageEnum.TELEGRAM)
                                .sendMessageTemplate(String.format(MESSAGE_CONFIG_DEAD_ACCOUNT_TEMPLATE,
                                        totalAccounts, inactiveAccounts, StringUtils.join(inactiveAccountNames, ",")));
                    } else {
                        messageFactory.getType(MessageEnum.TELEGRAM)
                                .sendMessageTemplate(String.format(MESSAGE_CONFIG_SUCCESS_ACCOUNT_TEMPLATE, totalAccounts));
                    }
                } catch (Exception e) {
                    log.warn("发送消息失败: {}", e.getMessage(), e);
                }

                emitter.complete();

            } catch (Exception e) {
                log.error("检测异常", e);
                try {
                    emitter.send(SseEmitter.event().name("error").data("检测异常：" + e.getMessage()));
                } catch (IOException ignored) {}
                emitter.completeWithError(e);
            }
        }).start();

        return emitter;
    }

    /**
    * @Description: 查询租户的审计日志
    * @Param: [java.lang.String]
    * @return: com.doubledimple.ociserver.pojo.response.base.ApiResponse
    * @Author: doubleDImple
    * @Date: 10/31/25 1:47 PM
    */
    @Override
    @UseSocksProxy
    public ApiResponse queryAuditLogs(AuditLogRequest auditLogRequest) {
        try {
            Tenant tenant = tenantRepository.findById(Long.valueOf(auditLogRequest.getTenantId()))
                    .orElseThrow(() -> new RuntimeException("未找到对应租户"));

            if (auditLogRequest.getStartDate() != null && !auditLogRequest.getStartDate().isEmpty()) {
                String startDate = auditLogRequest.getStartDate();
                String endDate = auditLogRequest.getEndDate();

                OciPageResult<OciAuditEventDto> result = auditLogUtils.listAuditEventsByDateRange(
                        tenant, startDate, endDate, auditLogRequest.getPageToken());
                return ApiResponse.success(result);
            }

            int days = auditLogRequest.getDays() > 0 ? auditLogRequest.getDays() : 1;
            OciPageResult<OciAuditEventDto> result =
                    auditLogUtils.listRecentAuditEvents(tenant, days, auditLogRequest.getPageToken());
            return ApiResponse.success(result);

        } catch (Exception e) {
            log.warn("审计日志查询出现异常, 原因: {}", e.getMessage(), e);
            return ApiResponse.error("审计日志查询出现异常");
        }
    }

    @Override
    public ResponseEntity<?> exportData() {
        Page<Tenant> allTenants = this.getAllTenants(1, 0, 1000);
        List<Tenant> tenants = allTenants.getContent();
        return doExport( tenants);
    }

    @Override
    public ResponseEntity<?> exportData(Long Id) {
        Page<Tenant> allTenantsByParentId = getAllTenantsByParentId(Id, 1, 0, 1000);
        List<Tenant> tenants = allTenantsByParentId.getContent();
        return doExport(tenants);
    }


    private ResponseEntity<?> doExport(List<Tenant> tenants){
        try {
            List<Map<String, Object>> result = new ArrayList<>();
            for (Tenant tenant : tenants) {
                Map<String, Object> tenantData = new HashMap<>();

                // 基本租户信息
                tenantData.put("id", tenant.getId());
                tenantData.put("tenant_id", tenant.getTenantId());
                tenantData.put("user_name", tenant.getUserName());
                tenantData.put("fingerprint", tenant.getFingerprint());
                tenantData.put("tenancy", tenant.getTenancy());
                tenantData.put("region", RegionEnum.getRegionCode(tenant.getRegion()));
                tenantData.put("created_at", tenant.getCreatedAt());
                tenantData.put("api_synced", Boolean.FALSE);
                tenantData.put("enable_icmp", tenant.getEnableIcmp());
                tenantData.put("enable_all_protocol", tenant.getEnableAllProtocol());
                tenantData.put("is_home_region", tenant.getIsHomeRegion());
                tenantData.put("paren_id", tenant.getParenId());
                tenantData.put("tenancy_name", tenant.getTenancyName());
                tenantData.put("tenancy_des", tenant.getTenancyDes());
                tenantData.put("account_type", tenant.getAccountType());
                tenantData.put("cloud_type", tenant.getCloudType());
                tenantData.put("region_en", tenant.getRegionEn());
                tenantData.put("id_str", tenant.getIdStr());
                tenantData.put("email_address", tenant.getEmailAddress());

                // 读取密钥文件内容
                String keyFilePath = tenant.getKeyFile();
                if (keyFilePath != null && !keyFilePath.isEmpty()) {
                    try {
                        String keyFileContent = new String(Files.readAllBytes(Paths.get(keyFilePath)), StandardCharsets.UTF_8);
                        tenantData.put("key_file_content", keyFileContent);
                    } catch (IOException e) {
                        log.warn("无法读取密钥文件: {}, 错误: {}", keyFilePath, e.getMessage());
                        tenantData.put("key_file_content", null);
                    }
                } else {
                    tenantData.put("key_file_content", null);
                }

                // 处理子租户信息
                List<Tenant> children = tenant.getChildren();
                List<Map<String, Object>> childrenData = new ArrayList<>();

                if (children != null && !children.isEmpty()) {
                    for (Tenant child : children) {
                        Map<String, Object> childData = new HashMap<>();
                        childData.put("id", child.getId());
                        childData.put("tenant_id", child.getTenantId());
                        childData.put("user_name", child.getUserName());
                        childData.put("fingerprint", child.getFingerprint());
                        childData.put("tenancy", child.getTenancy());
                        childData.put("region", RegionEnum.getRegionCode(child.getRegion()));
                        childData.put("created_at", child.getCreatedAt());
                        childData.put("api_synced", Boolean.FALSE);
                        childData.put("enable_icmp", child.getEnableIcmp());
                        childData.put("enable_all_protocol", child.getEnableAllProtocol());
                        childData.put("is_home_region", child.getIsHomeRegion());
                        childData.put("paren_id", child.getParenId());
                        childData.put("tenancy_name", child.getTenancyName());
                        childData.put("tenancy_des", child.getTenancyDes());
                        childData.put("account_type", child.getAccountType());
                        childData.put("cloud_type", child.getCloudType());
                        childData.put("region_en", child.getRegionEn());
                        childData.put("id_str", child.getIdStr());
                        childData.put("email_address", child.getEmailAddress());

                        // 读取子租户的密钥文件内容
                        String childKeyFilePath = child.getKeyFile();
                        if (childKeyFilePath != null && !childKeyFilePath.isEmpty()) {
                            try {
                                String childKeyFileContent = new String(Files.readAllBytes(Paths.get(childKeyFilePath)), StandardCharsets.UTF_8);
                                childData.put("key_file_content", childKeyFileContent);
                            } catch (IOException e) {
                                log.warn("无法读取子租户密钥文件: {}, 错误: {}", childKeyFilePath, e.getMessage());
                                childData.put("key_file_content", null);
                            }
                        } else {
                            childData.put("key_file_content", null);
                        }

                        childrenData.add(childData);
                    }
                }

                tenantData.put("children", childrenData);
                result.add(tenantData);
            }

            return ResponseEntity.ok(result);
        } catch (Exception e) {
            log.error("导出数据失败: {}", e.getMessage(), e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body("导出失败：" + e.getMessage());
        }
    }

    @Transactional
    @Override
    public void deleteApi(Long tenantIdReq,Boolean deleteFile) {
        List<Tenant> tenants = regionList(tenantIdReq);
        for (Tenant tenant : tenants) {
            String userName = tenant.getUserName();
            tenantRepository.deleteById(tenant.getId());
            if (deleteFile){
                deleteFile(tenant.getKeyFile());
            }
            //删除关联的实例
            List<BootInstance> bootInstances = bootInstanceRepository.queryBootInstanceByTenantId(tenant.getId());
            //如果有开机的boot,一律停止
            for (BootInstance bootInstance : bootInstances) {
                String uniqueId = userName + "_" + bootInstance.getId();
                //taskRepository.deleteTask(bootInstance.getBootId());
                createInstanceTask.deleteTask(bootInstance.getBootId());
                //CompletableFuture.runAsync(() -> messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplate(String.format(MESSAGE_CONFIG_STOP_TEMPLATE,userName,uniqueId)));
            }
            if (bootInstances.size() > 0) {
                List<Long> ids = bootInstances.stream()
                        .map(BootInstance::getId)
                        .collect(Collectors.toList());
                bootInstanceRepository.deleteAllByIdInBatch(ids);

                //删除实例预开数据
                List<String> bootIds = bootInstances.stream()
                        .map(BootInstance::getBootId)
                        .collect(Collectors.toList());
                ociComputerInfoRepository.deleteAllByBootIdStrInBatch(bootIds);
            }

            //delete async instance
            oracleInstanceDetailRepository.deleteByTenantId(tenant.getId());

            //删除邮箱配置
            emailService.deleteEmailConfig(tenant.getId());

            //删除分片上传记录
            ociMultipartUploadRecordRepository.deleteByTenantId(tenant.getId());

            //删除正在抢机中的任务
            //ociClassLoader.removeKey(tenant.getUserName());
        }
    }

    @Override
    @Transactional
    public synchronized void syncOci(Long tenantId) {
        Optional<Tenant> byId = tenantRepository.findById(tenantId);
        if (!byId.isPresent()) {
            log.warn("同步失败，租户不存在: {}", tenantId);
            return;
        }
        Tenant tenant = byId.get();
        // 统一走多云工厂：OCI / GCP 均写入 instance_detail（merge 本地字段）
        if (!cloudInstanceServiceFactory.supports(tenant.getCloudType())) {
            log.warn("租户[{}] cloudType={} 暂无实例同步实现", tenantId, tenant.getCloudType());
            return;
        }
        cloudInstanceServiceFactory.get(tenant.getCloudType()).syncToLocal(tenant);

        // GCP 兼容：同步后刷新 OTHER_BOOT_INSTANCE（旧 UI 仍可读）
        if (tenant.getCloudType() == CloudTypeEnum.GOOGLE_CLOUD.getType()) {
            try {
                refreshOtherBootFromInstanceDetail(tenant);
            } catch (Exception e) {
                log.warn("刷新 OTHER_BOOT_INSTANCE 兼容表失败: {}", tenantId, e);
            }
        }
    }

    /**
     * 将 instance_detail 中的 GCP 实例回写 OTHER 表，兼容旧列表页。
     */
    private void refreshOtherBootFromInstanceDetail(Tenant tenant) {
        List<InstanceDetails> details = oracleInstanceDetailRepository.findByTenantId(tenant.getId());
        Map<String, String> passwordMap = new HashMap<String, String>();
        List<OtherBootInstance> oldList = otherBootInstanceRepository.findByTenantIdAndCloudType(
                tenant.getId(), CloudTypeEnum.GOOGLE_CLOUD.getType());
        if (!CollectionUtils.isEmpty(oldList)) {
            for (OtherBootInstance o : oldList) {
                if (o.getInstanceName() != null && o.getRootPassword() != null) {
                    passwordMap.put(o.getInstanceName(), o.getRootPassword());
                }
            }
        }
        otherBootInstanceRepository.deleteByTenantId(tenant.getId());
        if (CollectionUtils.isEmpty(details)) {
            return;
        }
        List<OtherBootInstance> toSave = new ArrayList<OtherBootInstance>();
        for (InstanceDetails d : details) {
            if (d.getCloudType() != CloudTypeEnum.GOOGLE_CLOUD.getType()) {
                continue;
            }
            OtherBootInstance o = new OtherBootInstance();
            o.setBootId("gcp-" + (d.getInstanceId() == null ? UUID.randomUUID().toString().substring(0, 8) : d.getInstanceId()).replace("/", "-"));
            o.setTenantId(tenant.getId());
            o.setInstanceName(d.getDisplayName());
            o.setZone(d.getAvailabilityDomain());
            o.setOcpu(d.getOcpus() == null ? 1 : d.getOcpus());
            o.setMemory(d.getMemoryInGBs() == null ? 1 : d.getMemoryInGBs());
            o.setDisk(d.getBootVolumeSizeInGBs() == null ? 20 : d.getBootVolumeSizeInGBs().intValue());
            o.setInstanceCount(1);
            o.setPublicIp(StringUtils.defaultIfBlank(d.getPublicIps(), "0.0.0.0"));
            o.setArchitecture(StringUtils.defaultIfBlank(d.getArchitecture(), "X86_64"));
            o.setCloudType(CloudTypeEnum.GOOGLE_CLOUD.getType());
            String pwd = StringUtils.isNotBlank(d.getPassword()) ? d.getPassword()
                    : passwordMap.getOrDefault(d.getDisplayName(), "UNKNOW");
            o.setRootPassword(pwd);
            if ("RUNNING".equalsIgnoreCase(d.getState())) {
                o.setStatus(2);
            } else if ("PROVISIONING".equalsIgnoreCase(d.getState()) || "STAGING".equalsIgnoreCase(d.getState())) {
                o.setStatus(1);
            } else {
                o.setStatus(0);
            }
            o.setRemark(d.getRemark());
            toSave.add(o);
        }
        if (!toSave.isEmpty()) {
            otherBootInstanceRepository.saveAll(toSave);
        }
    }

    @Override
    public void globalSyncOci() {
        List<Tenant> allTenants = tenantRepository.findAll();
        if (!CollectionUtils.isEmpty(allTenants)) {
            int submitted = ociSyncQueueManager.submitAllTenants(allTenants);
            log.info("已将{}个租户的同步任务提交到队列，队列当前深度: {}",
                    submitted, ociSyncQueueManager.getQueueDepth());
        } else {
            log.info("没有找到需要同步的租户");
        }
    }

    @Override
    public List<User> listUsers(String tenantId) {
        Optional<Tenant> byId = tenantRepository.findById(Long.valueOf(tenantId));
        Tenant tenant = byId.get();
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        String compartmentId = provider.getTenantId();
        try(IdentityClient identityClient = IdentityClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
            ListUsersRequest request = ListUsersRequest.builder()
                    .compartmentId(compartmentId)
                    .build();
            List<User> items = identityClient.listUsers(request).getItems();
            log.debug("获取到的用户信息是:{}",items);
            return items;
        }
    }

    @Override
    public String createUser(String tenantId, String username,String email,String groupId) {
        return oracleInstanceService.createOciAdminUser(Long.valueOf(tenantId),username,email,groupId);
    }

    @Override
    public List<Map<String, Object>> fetchTenantAndBootInstanceData() {
        return tenantRepository.fetchTenantAndBootInstanceData();
    }

    @Transactional
    @Override
    public void importData(List<Map<String, Object>> requestData) {
        List<String> createdKeyFiles = new ArrayList<>();

        try {
            for (Map<String, Object> record : requestData) {
                String id = getStringValue(record, "id");
                if (id == null || id.trim().isEmpty()) {
                    log.warn("跳过无效记录：id 为空");
                    continue;
                }

                // 检查租户是否已存在（通过 tenantId 字段）
                Optional<Tenant> byId = tenantRepository.findById(Long.valueOf(id));
                if (byId.isPresent()) {
                    log.info("租户 {} 已存在，跳过导入", byId.get().getTenantId());
                    continue;
                }

                // 创建并保存父租户
                Tenant tenant = createTenantFromRecord(record, createdKeyFiles);
                Tenant savedTenant = tenantRepository.save(tenant);

                // 处理子租户
                @SuppressWarnings("unchecked")
                List<Map<String, Object>> childrenData = (List<Map<String, Object>>) record.get("children");
                if (childrenData != null && !childrenData.isEmpty()) {
                    for (Map<String, Object> childRecord : childrenData) {
                        String childId = getStringValue(childRecord, "id");
                        if (childId == null || childId.trim().isEmpty()) {
                            log.warn("跳过无效的子租户记录：id 为空");
                            continue;
                        }

                        // 检查子租户是否已存在
                        Optional<Tenant> existingChild = tenantRepository.findById(Long.valueOf(childId));
                        if (existingChild.isPresent()) {
                            log.info("子租户 {} 已存在，跳过导入", existingChild.get().getTenantId());
                            continue;
                        }

                        // 创建子租户
                        Tenant childTenant = createTenantFromRecord(childRecord, createdKeyFiles);
                        // 设置父租户关系
                        childTenant.setParenId(savedTenant.getId());

                        // 保存子租户
                        tenantRepository.save(childTenant);
                    }
                }
            }
            log.info("数据导入成功！共处理 " + requestData.size() + " 条记录");
        } catch (Exception e) {
            log.error("数据导入失败: {}", e.getMessage(), e);

            // 清理已创建的密钥文件
            for (String keyFilePath : createdKeyFiles) {
                try {
                    FileUtils.deleteFile(keyFilePath);
                } catch (Exception cleanupException) {
                    log.error("清理密钥文件失败: {}", cleanupException.getMessage());
                }
            }

            throw new RuntimeException("导入失败: " + e.getMessage());
        }
    }

    private Tenant createTenantFromRecord(Map<String, Object> record, List<String> createdKeyFiles) {
        Tenant tenant = new Tenant();

        // 设置所有字段（除了主键ID）
        tenant.setId(getLongValue(record, "id"));
        tenant.setTenantId(getStringValue(record, "tenant_id"));
        tenant.setUserName(getStringValue(record, "user_name"));
        tenant.setFingerprint(getStringValue(record, "fingerprint"));
        tenant.setTenancy(getStringValue(record, "tenancy"));
        tenant.setRegion(getStringValue(record, "region"));
        tenant.setApiSynced(getBooleanValue(record, "api_synced"));
        tenant.setEnableIcmp(getBooleanValue(record, "enable_icmp", false));
        tenant.setEnableAllProtocol(getBooleanValue(record, "enable_all_protocol", false));
        tenant.setIsHomeRegion(getBooleanValue(record, "is_home_region", true));
        tenant.setParenId(getLongValue(record, "paren_id"));
        tenant.setTenancyName(getStringValue(record, "tenancy_name"));
        tenant.setTenancyDes(getStringValue(record, "tenancy_des"));
        tenant.setAccountType(getStringValue(record, "account_type"));
        tenant.setCloudType(getIntegerValue(record, "cloud_type", 1));
        tenant.setRegionEn(getStringValue(record, "region_en"));
        tenant.setIdStr(getStringValue(record, "id_str"));
        tenant.setEmailAddress(getStringValue(record, "email_address"));

        // 处理创建时间
        String createdAtStr = getStringValue(record, "created_at");
        if (createdAtStr != null && !createdAtStr.trim().isEmpty()) {
            try {
                LocalDateTime createdAt = LocalDateTime.parse(createdAtStr, DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));
                tenant.setCreatedAt(createdAt);
            } catch (Exception e) {
                log.warn("解析创建时间失败: {}, 使用当前时间", createdAtStr);
                // 构造函数已经设置了当前时间，无需额外处理
            }
        }

        // 处理密钥文件
        String keyFileContent = getStringValue(record, "key_file_content");
        if (keyFileContent != null && !keyFileContent.trim().isEmpty()) {
            try {
                FileUtils.checkFile(baseFile);
                String keyFilePath = baseFile + UUID.randomUUID() + "_key.pem";
                Files.write(Paths.get(keyFilePath), keyFileContent.getBytes(StandardCharsets.UTF_8));
                tenant.setKeyFile(keyFilePath);
                createdKeyFiles.add(keyFilePath); // 记录创建的文件，用于异常时清理
            } catch (IOException e) {
                log.error("写入密钥文件失败: {}", e.getMessage(), e);
                throw new RuntimeException("写入密钥文件失败: " + e.getMessage());
            }
        }

        return tenant;
    }

    /**
     * 安全获取字符串值的辅助方法
     */
    private String getStringValue(Map<String, Object> record, String key) {
        Object value = record.get(key);
        return value != null ? value.toString().trim() : null;
    }

    /**
     * 安全获取布尔值的辅助方法
     */
    private Boolean getBooleanValue(Map<String, Object> record, String key) {
        Object value = record.get(key);
        if (value == null) return null;
        if (value instanceof Boolean) return (Boolean) value;
        String strValue = value.toString().toLowerCase().trim();
        return "true".equals(strValue) || "1".equals(strValue);
    }

    /**
     * 安全获取布尔值的辅助方法（带默认值）
     */
    private Boolean getBooleanValue(Map<String, Object> record, String key, Boolean defaultValue) {
        Boolean value = getBooleanValue(record, key);
        return value != null ? value : defaultValue;
    }

    /**
     * 安全获取长整型值的辅助方法
     */
    private Long getLongValue(Map<String, Object> record, String key) {
        Object value = record.get(key);
        if (value == null) return null;
        try {
            return Long.valueOf(value.toString());
        } catch (NumberFormatException e) {
            log.warn("无法解析长整型值: {} = {}", key, value);
            return null;
        }
    }

    /**
     * 安全获取整型值的辅助方法（带默认值）
     */
    private Integer getIntegerValue(Map<String, Object> record, String key, Integer defaultValue) {
        Object value = record.get(key);
        if (value == null) return defaultValue;
        try {
            return Integer.valueOf(value.toString());
        } catch (NumberFormatException e) {
            log.warn("无法解析整型值: {} = {}, 使用默认值: {}", key, value, defaultValue);
            return defaultValue;
        }
    }

    @Override
    public AccountCheckRes checkBatchAccounts() {
        //Page<Tenant> allTenants = getAllTenants(1,0, 1000);
        Page<Tenant> allTenants = findParentTenant(1, 0, 1000);
        // 添加null检查
        if (allTenants == null) {
            // 处理null情况，例如返回一个默认结果或日志记录
            log.warn("没有获取到租户信息");
            return new AccountCheckRes(0, 0, 0, new ArrayList<>());
        }
        List<Tenant> all = allTenants.getContent();
        int totalAccounts = all.size();
        int activeAccounts = 0;
        int inactiveAccounts = 0;
        List<Long> noActiveIds = new ArrayList<>();
        List<String> inactiveAccountNames = new ArrayList<>();
        if (!CollectionUtils.isEmpty(all)){
            for (Tenant tenant : all) {
                ResponseEntity<?> responseEntity = oracleInstanceService.checkAccountStatus(tenant.getId());
                boolean isActive = isStatusSuccess(responseEntity);
                if (isActive) {
                    activeAccounts++;
                } else {
                    noActiveIds.add(tenant.getId());
                    inactiveAccounts++;
                    String tenancyName = tenant.getTenancyName();
                    if (StringUtils.isBlank(tenancyName)){
                        tenancyName = tenant.getUserName();
                    }
                    inactiveAccountNames.add(tenancyName);
                }
            }
        }

        //发送消息
        try {
            //处理失效账号
            if (noActiveIds.size() > 0){
                tenantRepository.batchUpdateStatusToInactive(noActiveIds);
            }
            if (inactiveAccountNames.size() > 0){
                messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplate(String.format(MESSAGE_CONFIG_DEAD_ACCOUNT_TEMPLATE,totalAccounts,inactiveAccounts,StringUtils.join(inactiveAccountNames, ",")));
            }else {
                messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplate(String.format(MESSAGE_CONFIG_SUCCESS_ACCOUNT_TEMPLATE,totalAccounts));
            }
        } catch (Exception e) {
            log.warn("发送消息失败: {}", e.getMessage(), e);
        }
        return new AccountCheckRes(totalAccounts, activeAccounts, inactiveAccounts, inactiveAccountNames);

    }

    @Override
    public List<BootVolumeRes> getAllBootVolumes(String tenantId) {
        Optional<Tenant> byId = tenantRepository.findById(Long.valueOf(tenantId));
        Tenant tenant = byId.get();
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        try (BlockstorageClient blockstorageClient = BlockstorageClient.builder().build(provider)) {
            // 获取所有compartmentId
            List<String> allCompartmentIds = OciUtils.getAllCompartmentIds(tenant);

            // 创建结果集合
            List<BootVolumeRes> allBootVolumes = new ArrayList<>();

            // 遍历每个compartmentId查询引导卷
            for (String compartmentId : allCompartmentIds) {
                try {
                    ListBootVolumesRequest request = ListBootVolumesRequest.builder()
                            .compartmentId(compartmentId)
                            .build();

                    ListBootVolumesResponse response = blockstorageClient.listBootVolumes(request);

                    // 处理当前compartment的引导卷并添加到结果集合
                    List<BootVolumeRes> compartmentBootVolumes = response.getItems().stream()
                            .filter(bootVolume -> BootVolume.LifecycleState.Available.equals(bootVolume.getLifecycleState()))
                            .map(bootVolume -> {
                                BootVolumeRes bootVolumeRes = BootVolumeRes.fromBootVolume(bootVolume);
                                // 根据引导卷ID查询本地实例信息
                                // 获取List的第一个元素
                                oracleInstanceDetailRepository.findByBootVolumeId(bootVolume.getId())
                                        .stream()
                                        .findFirst()
                                        .ifPresent(instanceDetails -> {
                                            bootVolumeRes.setInstanceId(instanceDetails.getInstanceId());
                                            bootVolumeRes.setInstanceDetailsId(instanceDetails.getId());
                                            bootVolumeRes.setInstanceName(instanceDetails.getDisplayName());
                                            bootVolumeRes.setCompartmentId(compartmentId);
                                        });
                                return bootVolumeRes;
                            })
                            .collect(Collectors.toList());

                    allBootVolumes.addAll(compartmentBootVolumes);
                    log.debug("从compartment[{}]获取到{}个引导卷", compartmentId, compartmentBootVolumes.size());

                } catch (Exception e) {
                    // 记录错误但继续处理其他compartment
                    log.warn("获取compartment[{}]引导卷时出现异常: {}", compartmentId, e.getMessage());
                }
            }

            log.debug("共获取到{}个有效引导卷", allBootVolumes.size());
            return allBootVolumes;

        } catch (Exception e) {
            log.error("获取引导卷过程中出现异常: {}", e.getMessage(), e);
            throw new RuntimeException("获取引导卷失败: " + e.getMessage(), e);
        }
    }

    /**
    * @Description: 修改引导卷性能
    * @Param: [java.lang.String]
    * @return: void
    * @Author doubleDimple
    * @Date: 12/23/24 8:19 PM
    */
    @Override
    @Transactional
    public UpdateBootVolumeResponse updateBootVolumeVpus(String bootVolumeId, BootVolumeUpdateRequest request) {
        Optional<Tenant> byId = tenantRepository.findById(Long.valueOf(request.getTenantId()));
        if (!byId.isPresent()) {
            throw new RuntimeException("Tenant not found");
        }
        Tenant tenant = byId.get();
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        UpdateBootVolumeResponse response = null;

        try (BlockstorageClient blockstorageClient = BlockstorageClient.builder().build(provider)) {
            UpdateBootVolumeDetails.Builder updateDetailsBuilder = UpdateBootVolumeDetails.builder();

            // 只有当displayName不为空字符串时，才更新名称
            if (request.getDisplayName() != null && !request.getDisplayName().isEmpty()) {
                updateDetailsBuilder.displayName(request.getDisplayName());
            }

            // 只有当vpusPerGB不为-1时，才更新VPUs
            if (request.getVpusPerGB() != -1) {
                updateDetailsBuilder.vpusPerGB(request.getVpusPerGB());
            }

            UpdateBootVolumeDetails updateDetails = updateDetailsBuilder.build();

            UpdateBootVolumeRequest updateRequest = UpdateBootVolumeRequest.builder()
                    .bootVolumeId(bootVolumeId)
                    .updateBootVolumeDetails(updateDetails)
                    .build();

            response = blockstorageClient.updateBootVolume(updateRequest);
            // 同步vpusPerGB到本地数据库
            if (request.getInstanceDetailId() != null && request.getVpusPerGB() != null && request.getVpusPerGB() != -1) {
                Optional<InstanceDetails> instanceDetailsOpt = oracleInstanceDetailRepository.findById(request.getInstanceDetailId());
                if (instanceDetailsOpt.isPresent()) {
                    InstanceDetails instanceDetails = instanceDetailsOpt.get();
                    instanceDetails.setVpusPerGB(String.valueOf(request.getVpusPerGB()));
                    oracleInstanceDetailRepository.save(instanceDetails);
                }
            }
            return response;
        } catch (Exception e) {
            log.error("修改引导卷出现异常,原因为:{}", e.getMessage(), e);
            throw new RuntimeException("Failed to update boot volume", e);
        }
    }

    @Override
    public List<TenantDTO> getAllTenantsForDropdown() {
        List<Tenant> tenants = tenantRepository.findAll();

        return tenants.stream()
                .map(tenant -> {
                    TenantDTO dto = new TenantDTO();
                    dto.setTenantId(String.valueOf(tenant.getId()));
                    dto.setUserName(tenant.getRegion());
                    return dto;
                })
                .collect(Collectors.toList());
    }

    @Override
    public List<OciGroupResp> findGroups(String tenantId) {
        return oracleInstanceService.findGroup(Long.valueOf(tenantId));
    }

    @Override
    public List<Tenant> regionList(long tenantId) {
        List<Tenant> resultList = new ArrayList<>();
        // 查询指定的租户记录
        Optional<Tenant> tenantOptional = tenantRepository.findById(tenantId);

        if (tenantOptional.isPresent()) {
            Tenant parentTenant = tenantOptional.get();
            // 设置区域名称
            parentTenant.setRegion(RegionEnum.getNameByCode(parentTenant.getRegion()));
            if (getOpenInsTask(parentTenant.getId())){
                parentTenant.setOpenInsFlag("1");
            }
            String defName = "";
            Optional<CloudTenancy> parentCloudTenancy = cloudTenancyRepository.findByTenancyNameAndCloudTypeAndType(parentTenant.getTenancy(), parentTenant.getCloudType(),1);
            if (parentCloudTenancy.isPresent()){
                defName = parentCloudTenancy.get().getDefName();
            }else{
                defName = parentTenant.getUserName();
            }
            parentTenant.setDefName(defName);
            boolean childConSu = RegionEnum.getSupportAiRegion().contains(RegionEnum.getCodeByName(parentTenant.getRegion()));
            if (childConSu){
                parentTenant.setSupportAI(1);
            }
            boolean pb = bootInstanceRepository.existsRunningTaskByTenantId(parentTenant.getId());
            parentTenant.setOpenBootFlag(pb);

            // 获取所有子租户
            List<Tenant> children = tenantRepository.findByParenId(parentTenant.getId());

            if (!children.isEmpty()) {
                // 处理每个子记录
                String finalDefName = defName;
                children.forEach(child -> {
                    // 设置区域名称
                    child.setRegion(RegionEnum.getNameByCode(child.getRegion()));
                    if (getOpenInsTask(child.getId())){
                        child.setOpenInsFlag("1");
                    }
                    boolean b = bootInstanceRepository.existsRunningTaskByTenantId(child.getId());
                    child.setOpenBootFlag(b);
                    // 子记录没有下层记录
                    child.setHasChildren(false);
                    child.setDefName(finalDefName);
                    boolean childCon = RegionEnum.getSupportAiRegion().contains(RegionEnum.getCodeByName(child.getRegion()));
                    if (childCon){
                        child.setSupportAI(1);
                    }

                });

                parentTenant.setChildren(children);
                parentTenant.setHasChildren(true);
            } else {
                parentTenant.setHasChildren(false);
            }

            // 将父租户添加到结果列表
            resultList.add(parentTenant);

            // 将所有子租户也添加到结果列表
            resultList.addAll(children);
        }
        return resultList;
    }

    private boolean getOpenInsTask(Long tenantId) {
        final int i = bootInstanceRepository.countRunningTasksByTenantId(tenantId);
        if (i > 0){
            return true;
        }else {
            return false;
        }
    }

    @Override
    public Page<Tenant> searchTenants(String keyword,Integer cloudType, int page, int size) {
        Pageable pageable = PageRequest.of(page, size,Sort.by(
                        Sort.Order.desc("createdAt"),
                        Sort.Order.asc("region")
                )
        );

        // 使用自定义查询方法进行搜索
        Page<Tenant> searchResults = tenantRepository.searchByKeyword(keyword,cloudType, 0L, pageable);

        if (searchResults != null && !searchResults.getContent().isEmpty()) {
            List<Tenant> modifiedContent = new ArrayList<>();

            // 处理搜索结果
            for (Tenant parent : searchResults.getContent()) {
                Optional<CloudTenancy> byTenancyNameAndCloudType = cloudTenancyRepository.findByTenancyNameAndCloudTypeAndType(parent.getTenancy(), cloudType,1);
                if (byTenancyNameAndCloudType.isPresent()){
                    CloudTenancy cloudTenancy = byTenancyNameAndCloudType.get();
                    String cost = cloudTenancy.getAccountCost() == null ? "0" : cloudTenancy.getAccountCost();
                    parent.setDefName(cloudTenancy.getDefName());
                    parent.setAccountCost(cost);
                }else {
                    parent.setDefName(parent.getUserName());
                    parent.setAccountCost("0");
                }
                // 设置区域名称
                String regionName = RegionEnum.getNameByCode(parent.getRegion());
                parent.setRegion(regionName);
                parent.setIdStr(String.valueOf(parent.getId()));
                Optional<RegisterDetail> byTenantId = registerDetailRepository.findByTenantId(parent.getTenantId());
                if (byTenantId.isPresent()){
                    RegisterDetail registerDetail = byTenantId.get();
                    parent.setRegisterDetail(registerDetail);
                    Subscription.AccountType accountType = registerDetail.getAccountType();
                    Subscription.PlanType planType = registerDetail.getPlanType();
                    String accountTypeName = AccountTypeSubEnum.getByCode(accountType.getValue()) + PlanTypeSubEnum.getByCode(planType.getValue());
                    if (StringUtils.isNotBlank(accountTypeName)){
                        parent.setAccountTypeName(accountTypeName);
                    }else {
                        parent.setAccountTypeName("未知");
                    }
                    String activeDays = calculateDaysFromNow(registerDetail.getRegisterTime());
                    parent.setActiveDays(activeDays);
                }else {
                    parent.setAccountTypeName("未知");
                }
                boolean contains = RegionEnum.getSupportAiRegion().contains(RegionEnum.getCodeByName(parent.getRegion()));
                if (contains){
                    parent.setSupportAI(1);
                }

                AtomicReference<Boolean> openInsFlag = new AtomicReference<>(false);
                // 获取并处理子记录
                List<Tenant> children = tenantRepository.findByParenId(parent.getId());
                children.removeIf(child -> child.getId().equals(parent.getId()));
                if (!children.isEmpty()) {
                    children.forEach(child -> {
                        child.setRegion(RegionEnum.getNameByCode(child.getRegion()));
                        boolean childCon = RegionEnum.getSupportAiRegion().contains(RegionEnum.getCodeByName(child.getRegion()));
                        if (childCon){
                            child.setSupportAI(1);
                        }
                        if (openInsFlag.get().equals(Boolean.FALSE)){
                            Boolean openInsFlagChild = bootInstanceRepository.existsRunningTaskByTenantId(child.getId());
                            if (openInsFlagChild){
                                openInsFlag.set(true);
                            }
                        }
                        child.setChildren(null);
                    });
                    parent.setChildren(children);
                    parent.setHasChildren(true);
                } else {
                    parent.setHasChildren(false);
                }
                parent.setOpenBootFlag(openInsFlag.get());
                modifiedContent.add(parent);
            }

            fillProxyBoundFlags(modifiedContent);
            return new PageImpl<>(modifiedContent, searchResults.getPageable(), searchResults.getTotalElements());
        }

        return searchResults;
    }

    @Override
    public Page<Tenant> getTenantsByEmailEnable(Integer cloudType, int emailEnable, String keyword, int page, int size) {
        Pageable pageable = PageRequest.of(page, size, Sort.by(Sort.Order.desc("createdAt")));
        Page<Tenant> results;
        if (keyword != null && !keyword.trim().isEmpty()) {
            results = tenantRepository.findByCloudTypeAndEmailEnableAndKeyword(cloudType, emailEnable, keyword, pageable);
        } else {
            results = tenantRepository.findByCloudTypeAndEmailEnable(cloudType, emailEnable, pageable);
        }
        for (Tenant t : results.getContent()) {
            t.setIdStr(String.valueOf(t.getId()));
            Optional<CloudTenancy> ct = cloudTenancyRepository.findByTenancyNameAndCloudTypeAndType(t.getTenancy(), cloudType, 1);
            if (ct.isPresent()) {
                t.setDefName(ct.get().getDefName());
            } else if (t.getDefName() == null || t.getDefName().isEmpty()) {
                t.setDefName(t.getUserName());
            }
            String regionName = RegionEnum.getNameByCode(t.getRegion());
            if (regionName != null) t.setRegion(regionName);
        }
        return results;
    }

    /*@Override
    public List<Tenant> getParentTenants() {
         Page<Tenant> byParenIdIsNullOrParenId = tenantRepository.findByParenIdIsNullOrParenIdAndCloudType(0L,1, PageRequest.of(0, 1000));
         if (null !=byParenIdIsNullOrParenId ){
             List<Tenant> content = byParenIdIsNullOrParenId.getContent();
             for (Tenant tenant : content) {
                 Optional<RegisterDetail> byTenantId = registerDetailRepository.findByTenantId(tenant.getTenantId());
                 if (byTenantId.isPresent()){
                     RegisterDetail registerDetail = byTenantId.get();
                     tenant.setRegisterDetail(registerDetail);
                     Subscription.AccountType accountType = registerDetail.getAccountType();
                     Subscription.PlanType planType = registerDetail.getPlanType();
                     String accountTypeName = AccountTypeSubEnum.getByCode(accountType.getValue()) + PlanTypeSubEnum.getByCode(planType.getValue());
                     if (StringUtils.isNotBlank(accountTypeName)){
                         tenant.setAccountTypeName(accountTypeName);
                     }else {
                         tenant.setAccountTypeName("未知");
                     }
                     String activeDays = calculateDaysFromNow(registerDetail.getRegisterTime());
                     tenant.setActiveDays(activeDays);
                 }else {
                     tenant.setAccountTypeName("未知");
                 }
             }
             return content;
         }else {
             return new ArrayList<>();
         }
    }*/

    @Override
    public List<Tenant> getParentTenants() {
        Page<Tenant> byParenIdIsNullOrParenId = tenantRepository.findByParenIdIsNullOrParenIdAndCloudType(0L, 1, PageRequest.of(0, 1000));

        if (byParenIdIsNullOrParenId == null || byParenIdIsNullOrParenId.isEmpty()) {
            return new ArrayList<>();
        }

        List<Tenant> content = byParenIdIsNullOrParenId.getContent();
        List<String> tenantIds = content.stream()
                .map(Tenant::getTenantId)
                .filter(StringUtils::isNotBlank)
                .collect(Collectors.toList());

        if (tenantIds.isEmpty()) {
            return content;
        }

        List<RegisterDetail> registerDetails = registerDetailRepository.findByTenantIdIn(tenantIds);

        Map<String, RegisterDetail> registerDetailMap = registerDetails.stream()
                .collect(Collectors.toMap(RegisterDetail::getTenantId, detail -> detail, (existing, replacement) -> existing));

        for (Tenant tenant : content) {
            RegisterDetail registerDetail = registerDetailMap.get(tenant.getTenantId());

            if (registerDetail != null) {
                tenant.setRegisterDetail(registerDetail);

                Subscription.AccountType accountType = registerDetail.getAccountType();
                Subscription.PlanType planType = registerDetail.getPlanType();

                String accountTypeName = "";
                if (accountType != null && planType != null) {
                    accountTypeName = AccountTypeSubEnum.getByCode(accountType.getValue()) + PlanTypeSubEnum.getByCode(planType.getValue());
                }

                if (StringUtils.isNotBlank(accountTypeName)) {
                    tenant.setAccountTypeName(accountTypeName);
                } else {
                    tenant.setAccountTypeName("未知");
                }

                String activeDays = calculateDaysFromNow(registerDetail.getRegisterTime());
                tenant.setActiveDays(activeDays);
            } else {
                tenant.setAccountTypeName("未知");
            }
        }

        return content;
    }

    /**
    * 重置账号的验证因子
    */
    @Override
    public ApiResponse resetAccountFactor(Long tenantId) {
        Optional<Tenant> byId = tenantRepository.findById(tenantId);
        if (byId.isPresent()){
            Tenant tenant = byId.get();
            SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
            String userId = provider.getUserId();
            try(Identity identityClient = IdentityClient.builder()
                    .build(provider)) {
                // 3. 构建获取 MFA 设备列表的请求
                ListMfaTotpDevicesRequest listRequest = ListMfaTotpDevicesRequest.builder()
                        .userId(userId)
                        .build();

                // 获取 MFA 设备列表
                ListMfaTotpDevicesResponse response = identityClient.listMfaTotpDevices(listRequest);

                response.getItems().forEach(device -> {
                    String deviceId = device.getId();
                    if (log.isDebugEnabled()){
                        log.debug("设备ID: " + deviceId);
                        log.debug("设备状态: " + device.getLifecycleState());
                        log.debug("是否已激活: " + device.getIsActivated());
                        log.debug("最后更新时间: " + device.getTimeCreated());
                        log.debug("-----------------------------");
                    }

                    DeleteMfaTotpDeviceRequest deleteRequest = DeleteMfaTotpDeviceRequest.builder()
                            .userId(userId)
                            .mfaTotpDeviceId(device.getId())
                            .build();
                    identityClient.deleteMfaTotpDevice(deleteRequest);
                    log.info("当前租户:[{}]下的用户:[{}]重置验证因子成功",tenant.getTenancyName(),provider.getUserId());

                });
            } catch (Exception e) {
                log.error("获取验证因素列表时发生错误,原因是:[{}]",e.getMessage());
                return ApiResponse.error("重置验证因素失败,请稍后再试");
            }
        }
        return ApiResponse.success();
    }

    @Override
    public Map<String, Object> deleteBootVolume(Long tenantId, String volumeId) {
        Optional<Tenant> byId = tenantRepository.findById(tenantId);
        Map<String, Object> stringObjectMap = OciUtils.deleteBootVolume(byId.get(), volumeId);
        return stringObjectMap;
    }

    /**
    * @Description: 展示不重复的所有区域
    * @Param: []
    * @return: java.util.List<com.doubledimple.ocicommon.param.OpenRegionNotify>
    * @Author doubleDimple
    * @Date: 5/24/25 10:47 AM
    */
    @Override
    public List<OpenRegionNotify> listDisTenants() {
        List<OpenRegionNotify> results = new ArrayList<>();
        Set<String> uniqueRegions = new HashSet<>();
        List<Tenant> all = tenantRepository.findAll();
        if (all.size() > 0){
            for (Tenant tenant : all) {
                String regionCode = RegionEnum.getRegionCode(tenant.getRegion());
                if (!uniqueRegions.contains(regionCode)){
                    uniqueRegions.add(regionCode);
                    OpenRegionNotify openRegionNotify = new OpenRegionNotify();
                    openRegionNotify.setRegion(regionCode);
                    results.add(openRegionNotify);
                }
            }
        }
        return results;
    }

    @Override
    @Transactional
    public void updateAccountDetail(Long tenantId) {
        Optional<Tenant> byId = tenantRepository.findById(tenantId);
        if (byId.isPresent()){
            Tenant tenant = byId.get();
            Subscription subscription = OciGateWayUtils.getAccountTypeInfo(tenant);
            if (null != subscription){
                registerDetailService.saveRegisterDetail(tenant.getId(), tenant.getTenantId(), subscription);
            }
        }
    }

    @Override
    public Tenant getById(Long tenantId) {
        Optional<Tenant> byId = tenantRepository.findById(tenantId);
        if (byId.isPresent()){
            Tenant tenant = byId.get();
            //查询租户名称
            Optional<CloudTenancy> byTenancyNameAndCloudType = cloudTenancyRepository.findByTenancyNameAndCloudTypeAndType(tenant.getTenancy(), tenant.getCloudType(),1);
            if (byTenancyNameAndCloudType.isPresent()){
                tenant.setDefName(byTenancyNameAndCloudType.get().getDefName());
            }else {
                tenant.setDefName(tenant.getUserName());
            }
            return tenant;
        }else{
            return null;
        }
    }

    @Override
    public List<User> getPageUsers(String tenantId) {
        return listUsers(tenantId);
    }

    /**
     * 判断检测状态是否为成功
     */
    private boolean isStatusSuccess(ResponseEntity<?> responseEntity) {
        if (responseEntity.getBody() instanceof Map) {
            Map<String, Object> result = (Map<String, Object>) responseEntity.getBody();
            return "success".equals(result.get("status"));
        }
        return false;
    }

    @Override
    public ApiResponse assetAnalysis(Integer cloudType) {
        if (cloudType == null) {
            cloudType = 1;
        }
        Page<Tenant> allTenants = getAllTenants(cloudType, 0, 1000);
        List<Tenant> content = allTenants.getContent();
        long totalCount = content.size();
        long upgradeCount = content.stream()
                .filter(t -> "UPGRADE_ACCOUNT".equalsIgnoreCase(t.getAccountType()))
                .count();
        long freeCount = content.stream()
                .filter(t -> !"UPGRADE_ACCOUNT".equalsIgnoreCase(t.getAccountType()))
                .count();
        double totalCost = content.stream()
                .map(Tenant::getAccountCost)
                .filter(StringUtils::isNotBlank)
                .mapToDouble(Double::parseDouble)
                .sum();

        Map<String, Object> levelInfo = calculateUserLevel((int) totalCount);
        Map<String, Object> result = new HashMap<>();
        result.put("totalCount", totalCount);
        result.put("upgradeCount", upgradeCount);
        result.put("freeCount", freeCount);
        result.put("totalCost", String.format("%.2f", totalCost));
        result.put("level", levelInfo.get("level"));
        result.put("levelTitle", levelInfo.get("title"));
        return ApiResponse.success(result);
    }

    @Transactional(rollbackFor = Exception.class)
    public ApiResponse transferTenant(TenantTransferRequest request) {
        Optional<Tenant> tenantOptional = tenantRepository.findById(request.getTenantId());
        if (!tenantOptional.isPresent()) {
            return ApiResponse.error("未找到对应租户信息");
        }
        Tenant tenant = tenantOptional.get();
        List<BootInstance> bootInstances = bootInstanceRepository.queryBootInstanceByTenantId(tenant.getId());
        for (BootInstance bootInstance : bootInstances) {
            createInstanceTask.deleteTask(bootInstance.getBootId());
        }
        tenant.setTransferStatus(1);
        tenant.setTransferAmount(request.getTransferAmount());
        tenantRepository.save(tenant);
        return ApiResponse.success("转移成功");
    }

    @Override
    public void analyzeAllTenantsStream(SseEmitter emitter) {
         Page<Tenant> allTenants = getAllTenants(1, 0, 1000);
         List<Tenant> content = allTenants.getContent();
         if (content.size() > 0){
             chatAiService.analyzeAllTenantsStream(emitter,content);
         }
    }

    /**
    * @Description: 更新租户的资源信息
    * @Param: [java.lang.String, org.springframework.web.servlet.mvc.method.annotation.SseEmitter]
    * @return: void
    * @Author: doubleDimple
    * @Date: 2/27/26 10:32 AM
    */
    @Override
    public void updateTenantWithSSE(String tenantId, SseEmitter emitter) {
        CompletableFuture.runAsync(() -> {
            try {
                sendSseEvent(emitter, "progress", "开始更新租户及资源信息...");
                List<Tenant> tenants = self.updateTenancyDetail(tenantId);
                for (Tenant tenant : tenants) {
                    sendSseEvent(emitter, "progress", "开始更新租户[" + tenant.getUserName() + "]区域:["+tenant.getRegion()+"]实例资源...");
                    self.syncOci(tenant.getId());
                    //更新数据库信息
                    sendSseEvent(emitter, "progress", "开始更新租户[" + tenant.getUserName() + "]区域:["+tenant.getRegion()+"]数据库资源...");
                    dbConfigService.syncMysqlFromCloud(tenant.getId());
                }
                sendSseEvent(emitter, "success", "更新完成");
                emitter.complete();
            } catch (Exception e) {
                log.warn("租户[{}]更新失败, 原因为: {}", tenantId, e.getMessage());
                sendSseEvent(emitter, "error", "更新失败: " + e.getMessage());
                emitter.completeWithError(e);
            }
        });
    }

    @Override
    public void batchUpdateStatusToInactive(List<Long> inactiveTenantIds) {
        tenantRepository.batchUpdateStatusToInactive(inactiveTenantIds);
    }

    private void sendSseEvent(SseEmitter emitter, String eventName, String data) {
        try {
            emitter.send(SseEmitter.event().name(eventName).data(data));
        } catch (IOException e) {
            log.error("SSE 推送消息失败 [事件: {}]", eventName, e);
        }
    }

    /**
     * 根据账号数量判定等级
     */
    private Map<String, Object> calculateUserLevel(int count) {
        int level;
        String title;

        if (count >= 30) {
            level = 5; title = "🏅🏅🏅🏅🏅"; // 五枚勋章
        } else if (count >= 16) {
            level = 4; title = "🏅🏅🏅🏅";
        } else if (count >= 6) {
            level = 3; title = "🏅🏅🏅";
        } else if (count >= 3) {
            level = 2; title = "🏅🏅";
        } else {
            level = 1; title = "🏅";
        }

        Map<String, Object> map = new HashMap<>();
        map.put("level", level);
        map.put("title", title);
        return map;
    }
}
