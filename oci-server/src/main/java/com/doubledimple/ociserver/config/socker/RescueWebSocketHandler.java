package com.doubledimple.ociserver.config.socker;

import cn.hutool.json.JSONUtil;
import com.doubledimple.dao.entity.CloudSshConn;
import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.dao.entity.TemInstance;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.CloudSshConnRepository;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.ocicommon.enums.RegionEnum;
import com.doubledimple.ocicommon.param.ScriptResult;
import com.doubledimple.ocicommon.utils.JschUtils;
import com.doubledimple.ocicommon.utils.PasswordGenerator;
import com.doubledimple.ocicommon.utils.PingUtil;
import com.doubledimple.ociserver.pojo.domain.dto.OracleInstanceDetail;
import com.doubledimple.ociserver.pojo.domain.dto.User;
import com.doubledimple.ociserver.pojo.enums.AccountTypeEnum;
import com.doubledimple.ociserver.pojo.enums.ArchitectureEnum;
import com.doubledimple.ociserver.pojo.enums.MessageEnum;
import com.doubledimple.ociserver.config.event.InstanceBackUpEvent;
import com.doubledimple.ociserver.utils.oracle.OciClassLoader;
import com.doubledimple.ociserver.service.message.factory.MessageFactory;
import com.doubledimple.ociserver.service.oracle.OracleInstanceService;
import com.doubledimple.ociserver.pojo.response.BootVolumeRes;
import com.doubledimple.ociserver.pojo.response.InstanceDetailsRes;
import com.doubledimple.ociserver.pojo.response.TmpInstanceResponse;
import com.doubledimple.ociserver.service.InstanceDetailsService;
import com.doubledimple.ociserver.service.OciSshConnService;
import com.doubledimple.ociserver.service.OpenApiService;
import com.doubledimple.ociserver.service.oracle.OracleCloudService;
import com.doubledimple.ociserver.service.SecurityRuleService;
import com.doubledimple.ociserver.service.TemInstanceService;
import com.doubledimple.ociserver.service.TenantService;
import com.doubledimple.ociserver.utils.oracle.OciObjectStorageUtil;
import com.doubledimple.ociserver.utils.oracle.OciBackUpUtils;
import com.doubledimple.ociserver.utils.oracle.OciUtils;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.core.model.BootVolume;
import com.oracle.bmc.core.model.BootVolumeBackup;
import com.oracle.bmc.core.model.Instance;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.data.domain.Page;
import org.springframework.stereotype.Component;
import org.springframework.util.CollectionUtils;
import org.springframework.util.StopWatch;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.handler.TextWebSocketHandler;

import javax.annotation.PreDestroy;
import javax.annotation.Resource;
import java.io.IOException;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

import static com.doubledimple.ocicommon.enums.RegionEnum.getNotSupportHelp;
import static com.doubledimple.ocicommon.enums.RegionEnum.getRegionCode;
import static com.doubledimple.ocicommon.template.MessageTemplate.MESSAGE_RESCUE_SUCCESS_TEMPLATE;
import static com.doubledimple.ocicommon.utils.JschUtils.DF_SCRIPT;
import static com.doubledimple.ocicommon.utils.JschUtils.UPGRADE_AND_INIT_SCRIPT;
import static com.doubledimple.ocicommon.utils.JschUtils.changeRootPassword;
import static com.doubledimple.ocicommon.utils.JschUtils.enableRootLogin;
import static com.doubledimple.ocicommon.utils.JschUtils.executeOciRescueCommands2;
import static com.doubledimple.ocicommon.utils.JschUtils.getRescueStatus;
import static com.doubledimple.ocicommon.utils.JschUtils.verifyPasswordChange;
import static com.doubledimple.ocicommon.utils.PasswordGenerator.HELP_INIT_PASSWORD;
import static com.doubledimple.ociserver.config.constant.GenPojoUtils.bootPojo;
import static com.doubledimple.ociserver.utils.oracle.OciBackUpUtils.createBootVolumeBackup;
import static com.doubledimple.ociserver.utils.oracle.OciBackUpUtils.createBootVolumeFromBackup;
import static com.doubledimple.ociserver.utils.oracle.OciUtils.DEFAULT_PASSWD;
import static com.doubledimple.ociserver.utils.oracle.OciUtils.cloneBootVolumeFromBootVolume;
import static com.doubledimple.ociserver.utils.oracle.OciUtils.deleteBootVolume;
import static com.doubledimple.ociserver.utils.oracle.OciUtils.getAvailabilityDomainByInstanceId;
import static com.doubledimple.ociserver.utils.oracle.OciUtils.getBootVolume;
import static com.doubledimple.ociserver.utils.oracle.OciUtils.getInstanceById;
import static com.doubledimple.ociserver.utils.oracle.OciUtils.getProvider;
import static com.doubledimple.ociserver.utils.oracle.OciUtils.isBootVolumeTerminated;
import static com.doubledimple.ociserver.utils.oracle.OciUtils.terminateBootVolume;

/**
 * @version 1.0.0
 * @ClassName RescueWebSocketHandler
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-03-22 23:32
 */
@Slf4j
@Component("rescueWebSocketHandler")
@Qualifier("rescueWebSocketHandler")
public class RescueWebSocketHandler extends TextWebSocketHandler {

    @Resource
    OracleInstanceService oracleInstanceService;

    @Resource
    TenantRepository tenantRepository;

    @Resource
    private OracleCloudService oracleCloudService;

    @Resource
    TemInstanceService temInstanceService;

    @Resource
    private TenantService tenantService;

    @Resource
    private MessageFactory messageFactory;

    @Resource
    InstanceDetailsService instanceDetailsService;

    @Resource
    OpenApiService openApiService;

    @Resource
    private ApplicationEventPublisher eventPublisher;

    @Resource
    OciSshConnService ociSshConnService;

    @Resource
    SecurityRuleService securityRuleService;

    @Resource
    OciClassLoader ociClassLoader;

    @Resource
    CloudSshConnRepository cloudSshConnRepository;

    @Resource
    ScheduledThreadPoolExecutor delayedTaskExecutor;


    private final Map<String, Object> sessionLocks = new ConcurrentHashMap<>();
    private final ObjectMapper objectMapper = new ObjectMapper();

    private final Map<String, Future<?>> sessionTasks = new ConcurrentHashMap<>();

    // 新增线程池，用于处理救援任务
    private final ExecutorService executorService = Executors.newCachedThreadPool();
    // 新增调度线程池，用于定期检查救援状态
    private final ScheduledExecutorService scheduledExecutorService = Executors.newScheduledThreadPool(2);

    private final ScheduledExecutorService heartbeatExecutor = Executors.newSingleThreadScheduledExecutor();

    private ConcurrentHashMap<String, AtomicInteger> failureCountMap = new ConcurrentHashMap<>();

    //private static final AtomicBoolean rescueInProgress = new AtomicBoolean(false);

    private final Object messageLock = new Object();



    @Override
    public void afterConnectionEstablished(WebSocketSession session) {
        // 添加心跳检测
        heartbeatExecutor.scheduleAtFixedRate(() -> {
            try {
                if (session.isOpen()) {
                    Map<String, Object> heartbeat = new HashMap<>();
                    heartbeat.put("type", "heartbeat");
                    session.sendMessage(new TextMessage(objectMapper.writeValueAsString(heartbeat)));
                }
            } catch (IOException e) {
                log.error("发送心跳失败", e);
            }
        }, 0, 30, TimeUnit.SECONDS);
    }

    @Override
    protected void handleTextMessage(WebSocketSession session, TextMessage message) throws Exception {
        try {
            log.info("收到WebSocket消息: {}", message.getPayload());
            Map<String, Object> request = objectMapper.readValue(message.getPayload(), Map.class);
            String type = (String) request.get("type");
            log.info("消息类型: {}", type);

            switch (type) {
                case "init":
                    String instanceId = (String) request.get("instanceId");
                    Integer rescueType = (Integer) request.get("rescueType");
                    // 如果已经有救援操作在进行中，拒绝新的请求

                    handleRescueInit(session, instanceId,rescueType);
                    break;
                case "heartbeat":
                    // 处理心跳请求
                    Map<String, Object> response = new HashMap<>();
                    response.put("type", "heartbeat");
                    String jsonResponse = objectMapper.writeValueAsString(response);
                    session.sendMessage(new TextMessage(jsonResponse));
                    break;
                case "heartbeat_response":
                    // 心跳响应，只需记录日志
                    log.debug("收到心跳响应");
                    break;
                default:
                    log.debug("收到未知类型的消息: {}", type);
                    break;
            }
        } catch (Exception e) {
            log.error("处理WebSocket消息时出错", e);
            sendError(session, "处理消息失败: " + e.getMessage());
        }
    }

    /**
     * 处理系统救援初始化
     * 1:停机
     * 2:分离引导卷
     * 3:新建一台amd
     * 4:在新建的amd里面将分离的引导卷执行附加,挂载方式选择半虚拟化
     * 5:连接新建的amd
     * 6:使用 lsblk 或 fdisk -l 命令查看附加的ARM引导卷，一般是 /dev/sdb
     * 7:下载救援包 dabian10.arm.img.gz
     * 8:写入引导卷 gzip -dc /root/dabian10.arm.img.gz | dd of=/dev/sdb
     * 9:卸载附加的快存储卷
     * 10:将引导卷重新挂载
     */
    public void handleRescueInit(WebSocketSession session, String id,Integer rescueType) {
        log.info("Starting rescue process for instance: {}", id);
        StopWatch stopWatch = new StopWatch();
        stopWatch.start("救机耗时统计");
        if (id == null || id.trim().isEmpty()) {
            sendError(session, "Invalid instance ID");
            return;
        }


        boolean operationCompleted = false;

        // 将救援过程放入线程池执行，避免阻塞WebSocket线程
         Future<?> future = executorService.submit(() -> {
            try {
                // 检查实例存在性(需要救援的实例)
                InstanceDetails instanceById = oracleInstanceService.getInstanceById(Long.valueOf(id));
                if (instanceById == null) {
                    sendError(session, "当前实例不存在");
                    return;
                }
                String instanceId = instanceById.getInstanceId();

                // 检查租户存在性
                Optional<Tenant> byId = tenantRepository.findById(instanceById.getTenantId());
                if (!byId.isPresent()) {
                    sendError(session, "租户不存在");
                    return;
                }

                //查询下主区域的regionsCode
                Tenant tenant = byId.get();
                String sourceRegionCode = StringUtils.EMPTY;
                Long parenId = tenant.getParenId();
                Tenant parentTenant = null;
                if (null != parenId && parenId != 0L) {
                    Optional<Tenant> parentBy = tenantRepository.findById(parenId);
                    if (parentBy.isPresent()) {
                        parentTenant = parentBy.get();
                        sourceRegionCode = getRegionCode(parentTenant.getRegion());
                    } else {
                        parentTenant = byId.get();
                    }
                } else {
                    parentTenant = byId.get();
                }

                //对租户执行一次网络规则开通
                securityRuleService.checkAndEnableRule(tenant);

                String regionCode = getRegionCode(tenant.getRegion());
                sendMessage(session, "[实例操作] 开始执行...\r\n");
                //需要判断api权限,如果权限不足,不允许救援或者重置
                String accountType = tenant.getAccountType();
                if (StringUtils.isEmpty(accountType) || accountType.equals(AccountTypeEnum.UN_KNOW_ACCOUNT.getType())) {
                    sendError(session, "[实例操作] 当前租户API权限不足,无法执行救援操作,退出救援,请重新配置API后再试,...\r\n");
                    closeWebsocket(session);
                    return;
                }

                SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
                try {

                    //第0步:检查引导卷配额
                    List<BootVolumeRes> allBootVolumes = tenantService.getAllBootVolumes(String.valueOf(tenant.getId()));
                    //todo 这里暂时不清理 清理无关联的引导卷
                    /*allBootVolumes.forEach(bootVolumeRes -> {
                        if (bootVolumeRes.getInstanceId() == null){
                            // 清理无用引导卷
                            tenantService.deleteBootVolume(tenant.getId(), bootVolumeRes.getId());
                        }
                    });*/
                    String s = OciUtils.validateBootVolumes(allBootVolumes);

                    // 第一步:停止实例
                    sendMessage(session, "[实例操作] 正在停止实例...\r\n");
                    OciUtils.stopInstance(provider, instanceById.getInstanceId());
                    sendMessage(session, "[实例操作] 实例已成功停止\r\n");
                    String architecture = instanceById.getArchitecture();
                    //救援架构
                    String sourceArchitecture = architecture;
                    //救援实例的可用性域
                    String sourceAvailabilityDomain = instanceById.getAvailabilityDomain();

                    BootVolumeBackup homeRegionBackUpVolume = getHomeRegionBackUpVolume(tenant, instanceById);
                    TmpInstanceResponse tmpInstanceRes = null;
                    if (null == homeRegionBackUpVolume) {
                        //如果救援机是amd,不存在备份卷,不支持救援
                        if (architecture.equalsIgnoreCase("AMD")) {
                            sendError(session, "[注意] 当前实例不支持救援,请选择其他实例进行救援,退出救援,请重新选择实例后再试,...\r\n");
                            closeWebsocket(session);
                            return;
                        }

                        tmpInstanceRes = getAlreadyAmdInstance(instanceId, tenant, session, "AMD", false);
                        List<String> notSupportHelp = getNotSupportHelp();
                        if (null == tmpInstanceRes && notSupportHelp.contains(regionCode)) {
                            sendError(session, "[注意] 当前实例区域不支持救援,请选择其他实例进行救援,退出救援,请重新选择实例后再试,...\r\n");
                            closeWebsocket(session);
                            return;
                        }
                    }

                    // 第二步:分离引导卷,返回引导卷id
                    //sendMessage(session, "[引导卷操作] 开始分离引导卷...\r\n");
                    sendMessage(session, "[实例操作] 开始执行实例引导卷初始化\r\n");
                    String bootVolumeId = OciUtils.detachBootVolume(provider, instanceId);
                    //救援实例的最初引导卷id
                    final String earliestBootVolumeId = bootVolumeId;
                    //sendMessage(session, "[引导卷操作] 引导卷 " + bootVolumeId + " 已成功分离\r\n");
                    sendMessage(session, "[实例操作] 实例引导卷初始化成功\r\n");

                    if (s != null) {
                        //todo 先不删除引导军
                        //deleteBootVolume(tenant, bootVolumeId);
                    }


                    //如果是重置硬盘,需要终止当前引导卷
                    if (rescueType == 2) {
                        if (bootVolumeId != null && !bootVolumeId.isEmpty() && null == homeRegionBackUpVolume) {
                            sendMessage(session, "[引导卷操作] 开始终止引导卷...\r\n");
                            terminateBootVolume(tenant, bootVolumeId);
                            sendMessage(session, "[引导卷操作] 引导卷终止成功\r\n");
                        }
                    }

                    if (null == architecture || architecture.equalsIgnoreCase("NONE")) {
                        architecture = OciUtils.getArchitectureByInstanceId(tenant, instanceId);
                    }
                    if (null != homeRegionBackUpVolume) {
                        //存在备份引导卷,直接从备份还原并挂载
                        boolean b = doHelpFromBootVolumeBackup(session, bootVolumeId, tenant, instanceById, homeRegionBackUpVolume, sourceRegionCode, parentTenant);
                        if (b) {
                            closeWebsocket(session);
                            return;
                        } else {
                            log.warn("实例从备份救援失败,需要继续救援,,,,,,");
                            sendMessage(session, "[救援服务] 系统切换救援方式再次执行救援服务开始....\r\n");
                        }
                    } else {
                        //如果救援机是amd,不存在备份卷,不支持救援
                        if (architecture.equalsIgnoreCase("AMD")) {
                            sendError(session, "[引导卷操作] 当前实例不支持救援,请选择其他实例进行救援,退出救援,请重新选择实例后再试,...\r\n");
                            closeWebsocket(session);
                            return;
                        }
                    }

                    //默认fasle,未终止
                    boolean bootTerminated = false;
                    if (isBootVolumeTerminated(provider, bootVolumeId)) {
                        log.debug("原实例引导卷:{}已终止, 不能执行附加", bootVolumeId);
                        bootVolumeId = null;
                        bootTerminated = true;
                    }

                    // 第三步,新建一台amd,(可能在任何可用性域)
                    //先检测租户下是否存在amd实例
                    String helpArchitecture = ArchitectureEnum.AMD.getType();
                    //判断当前租户是否存在amd实例,如果存在,使用已经存在的amd实例
                    String password = DEFAULT_PASSWD;
                    if (null == tmpInstanceRes) {
                        tmpInstanceRes = getAlreadyAmdInstance(instanceId, tenant, session, helpArchitecture, bootTerminated);
                    }

                    List<TemInstance> temInstanceList = temInstanceService.findByTenancyAndRegionAndArchitecture(tenant.getTenancy(), regionCode, helpArchitecture);
                    TemInstance temInstance = new TemInstance();
                    String newInstanceId = "";
                    if (!CollectionUtils.isEmpty(temInstanceList)) {
                        temInstance = temInstanceList.get(0);
                        newInstanceId = temInstance.getInstanceId();
                        Instance instance = getInstanceById(tenant, newInstanceId);
                        if (null == instance ||
                                instance.getLifecycleState().equals(Instance.LifecycleState.Terminated) ||
                                instance.getLifecycleState().equals(Instance.LifecycleState.Terminating)) {
                            //需要删除表里的临时实例
                            temInstanceService.deleteByTenancy(tenant.getTenancy(), getRegionCode(tenant.getRegion()), helpArchitecture);
                            if (null == tmpInstanceRes) {
                                tmpInstanceRes = createTmpInstance(instanceId, earliestBootVolumeId, temInstance, regionCode, session, tenant, helpArchitecture, bootTerminated);
                            }
                            newInstanceId = tmpInstanceRes.getNewInstanceId();
                        } else {
                            newInstanceId = instance.getId();
                            tmpInstanceRes = new TmpInstanceResponse();
                            tmpInstanceRes.setInstance(instance);
                            tmpInstanceRes.setUser(bootPojo(tenant, helpArchitecture));
                            tmpInstanceRes.setNewInstanceId(instance.getId());
                            if (bootTerminated) {
                                String cloneBootVolumeId = cloneBootVolumeFromBootVolume(tenant, getBootVolume(instance, tenant).getId(), System.currentTimeMillis() + "_new", 50L);
                                tmpInstanceRes.setCloneBootVolumeId(cloneBootVolumeId);
                            }
                        }
                    } else {
                        if (null == tmpInstanceRes) {
                            tmpInstanceRes = createTmpInstance(instanceId, earliestBootVolumeId, temInstance, regionCode, session, tenant, helpArchitecture, bootTerminated);
                        }
                        newInstanceId = tmpInstanceRes.getNewInstanceId();
                        temInstance.setInstanceId(newInstanceId);
                        temInstance.setPublicIp(tmpInstanceRes.getInstanceDetails().getPublicIps());
                        password = tmpInstanceRes.getInstanceDetails().getPassword();
                        temInstance.setRootPasswd(tmpInstanceRes.getInstanceDetails().getPassword());
                    }


                    //如果原实例的引导卷被终止了,这里需要重新生成一个引导卷
                    //临时实例的可用性域
                    String tmpAvailabilityDomain = tmpInstanceRes.getInstance().getAvailabilityDomain();
                    String deleteCloneBootVolumeId = "";
                    if (bootTerminated) {
                        String cloneBootVolumeId = tmpInstanceRes.getCloneBootVolumeId();
                        if (null == cloneBootVolumeId) {
                            //重新生成一次
                            cloneBootVolumeId = cloneBootVolumeFromBootVolume(tenant, getBootVolume(tmpInstanceRes.getInstance(), tenant).getId(), System.currentTimeMillis() + "_new", 50L);
                            if (null == cloneBootVolumeId) {
                                sendError(session, "[引导卷操作] 引导卷超出配额,无法执行救援,...\r\n");
                                closeWebsocket(session);
                                return;
                            }
                            temInstance.setCloneBootVolumeId(cloneBootVolumeId);
                        }
                        deleteCloneBootVolumeId = cloneBootVolumeId;
                        bootVolumeId = cloneBootVolumeId;
                    }

                    //是否需要删除临时实例 false:不删除,  true:删除
                    final boolean deleteInsFlag = tmpInstanceRes.isDeleteInsFlag();
                    //后续步骤是否需要再次判断可用性域的 true:已经校验过,false需要校验
                    if (Objects.nonNull(bootVolumeId)) {
                        // 第四步,之前分离的引导卷执行附加到新建实例,挂载方式选择半虚拟化
                        sendMessage(session, "[救援服务] 开始执行救援步骤,请等待...\r\n");
                        // 需要校验救援实例的可用性域和新建的临时实例的可用性域是否相同,不相同,需要从备份创建新的引导卷
                        if (sourceAvailabilityDomain.equals(tmpAvailabilityDomain)) {
                            OciUtils.tachVolume(provider, temInstance, bootVolumeId);
                        } else {
                            String cloneBootVolumeId = temInstance.getCloneBootVolumeId();
                            if (StringUtils.isNotBlank(cloneBootVolumeId)) {
                                OciUtils.tachVolume(provider, temInstance, cloneBootVolumeId);
                            } else {
                                //再克隆一次
                                cloneBootVolumeId = cloneBootVolumeFromBootVolume(tenant, tmpInstanceRes.getInstanceDetails().getBootVolumeId(), System.currentTimeMillis() + "_new", 50L);
                                if (null != cloneBootVolumeId) {
                                    bootVolumeId = cloneBootVolumeId;
                                    OciUtils.tachVolume(provider, temInstance, cloneBootVolumeId);
                                    //如果clone成功,需要删除原实例的引导卷(不在同一个可用性域)
                                    deleteBootVolume(tenant, earliestBootVolumeId);
                                } else {
                                    sendError(session, "[引导卷操作] 引导卷超出配额,无法执行救援,...\r\n");
                                    closeWebsocket(session);
                                    return;
                                }
                            }

                        }
                        sendMessage(session, "[救援服务] 救援服务第一步已成功完成,开始执行第二步骤\r\n");
                    }
                    final String sourceBootVolumeId = bootVolumeId;

                    // 使用ssh执行连接新建的amd
                    //sendMessage(session, "[远程连接] 正在连接临时实例...\r\n");
                    sendMessage(session, "[救援服务] 救援服务第二步骤正在执行中,请等待...\r\n");
                    String host = temInstance.getPublicIp();
                    String username = "root";

                    //这里等待一会,等待实例网络初始化完成
                    Thread.sleep(10000);

                    if (!PingUtil.ping(host).isReachable()) {
                        log.debug("当前ip无法ping通,执行协议开启后再次尝试");
                        securityRuleService.checkAndEnableRule(tenant);
                    }

                    //校验是否可以连接,再写入镜像
                    boolean sshConFlag = verifyPasswordChange(host, password);
                    if (sshConFlag) {
                        ScriptResult root = enableRootLogin(temInstance.getPublicIp(), "root", temInstance.getRootPasswd(), temInstance.getRootPasswd(), 22);
                        if (root.isSuccess()) {
                            log.debug("root用户登录成功");
                        } else {
                            log.debug("root用户登录失败");
                        }
                        //instanceDetailsService.doBootVolumeBackUpNoAuth(tmpInstanceRes.getInstanceDetails(), tmpInstanceRes.getUser(), tmpInstanceRes.getTmpBootVolumeId());
                        sendMessage(session, "[救援服务] 实例初始化检测成功...\r\n");
                    } else {
                        sendError(session, "[救援服务] 实例初始化检测异常,ip无法连接,请稍后再试...\r\n");
                        temInstanceService.deleteByTenancyAndRegionAndArchitecture(tenant.getTenancy(), getRegionCode(tenant.getRegion()), architecture, provider, newInstanceId, deleteInsFlag);
                        //同步一次实例
                        sendMessage(session, "[救援服务] 救援服务正在停止中,请稍后...\r\n");
                        tenantService.syncOci(tenant.getId());
                        sendMessage(session, "[救援服务] 救援服务停止成功...\r\n");
                        closeWebsocket(session);
                        return;
                    }

                    //oci-Start2025 镜像默认密码
                    JschUtils.RescueStatus rescueStatus = executeOciRescueCommands2(host, username, password, session, bootTerminated);
                    if (rescueStatus.getStatus().equals("failed")) {
                        closeWebsocket(session);
                        return;
                    }
                    sendMessage(session, "[救援服务] 救援服务第二步骤执行成功完成,开始初始化实例\r\n");


                    // 使用调度线程池定期检查状态，而不是阻塞当前线程
                    AtomicBoolean completed = new AtomicBoolean(false);
                    String finalNewInstanceId = newInstanceId;
                    User finalUser = tmpInstanceRes.getUser();
                    finalUser.setArchitecture(architecture);
                    String finalArchitecture = architecture;
                    boolean finalBootTerminated = bootTerminated;
                    String finalDeleteCloneBootVolumeId = deleteCloneBootVolumeId;
                    String finalPassword = password;
                    scheduledExecutorService.scheduleAtFixedRate(() -> {
                        try {
                            if (completed.get()) {
                                return; // 如果已完成则不再检查
                            }
                            // 添加重试机制
                            int maxRetries = 3;
                            int currentRetry = 0;
                            JschUtils.RescueStatus status = null;

                            while (currentRetry < maxRetries) {
                                try {
                                    status = getRescueStatus(host, username, finalPassword);
                                    break; // 成功获取状态，跳出重试循环
                                } catch (Exception retryEx) {
                                    currentRetry++;
                                    if (currentRetry >= maxRetries) {
                                        throw retryEx; // 重试次数用完，抛出异常
                                    }
                                    log.warn("临时连接失败(可能是系统重启中)，正在重试 ({}/{}): {}",
                                            currentRetry, maxRetries, retryEx.getMessage());
                                    // 等待几秒后重试
                                    Thread.sleep(5000);
                                }
                            }

                            if (status != null) {
                                if ("failed".equals(status.getStatus())) {
                                    sendError(session, "[救援服务] 救援流程执行失败: " + status.getMessage());
                                    completed.set(true);
                                } else if ("completed".equals(status.getStatus())) {
                                    //sendMessage(session, "救援镜像写入完成，继续执行后续操作\r\n");
                                    sendMessage(session, "[救援服务] 救援镜像写入成功，继续执行后续操作...\r\n");
                                    completed.set(true);

                                    // 第五步:释放挂载在临时实例的引导卷
                                    OciUtils.detachVolumeAttachment(provider, finalNewInstanceId);

                                    //需要判断原实例的可用性域和临时实例的可用性域是都相同,不相同的,需要执行备份临时实例挂载
                                    if (!sourceAvailabilityDomain.equals(tmpAvailabilityDomain)) {
                                        //克隆的实例相当于重新安装了系统
                                        String bootVolumeBackupId = createBootVolumeBackup(tenant, sourceBootVolumeId, sourceArchitecture);
                                        //从备份创建符合当前救援实例的引导卷
                                        String bootVolumeFromBackup = createBootVolumeFromBackup(tenant, regionCode, bootVolumeBackupId, sourceAvailabilityDomain);
                                        //备份还原的引导卷执行挂载
                                        OciUtils.attachBootVolume(provider, instanceById.getInstanceId(), bootVolumeFromBackup);
                                    } else {
                                        //第六步:重新挂载引导卷到救援实例
                                        //OciUtils.attachBootVolume(provider, instanceById.getInstanceId(), sourceBootVolumeId);
                                        attachBootVolumeWithRetry(provider, instanceById.getInstanceId(), sourceBootVolumeId);
                                    }

                                    // 第七步:重新引导救援的实例
                                    sendMessage(session, "[救援服务] 正在重新启动实例...\r\n");
                                    //OciUtils.startInstance(provider, instanceById.getInstanceId());
                                    OciUtils.resetInstance(tenant, instanceById.getInstanceId());
                                    sendMessage(session, "[救援服务] 实例重启成功...\r\n");

                                    String currentPwd = HELP_INIT_PASSWORD;
                                    instanceById.setPassword(currentPwd);
                                    instanceById.setArchitecture(finalArchitecture);
                                    InstanceDetails instanceDetails = new InstanceDetails();
                                    instanceDetails.setUsername("root");
                                    instanceDetails.setInstanceId(instanceById.getInstanceId());
                                    instanceDetails.setPort(22);

                                    Thread.sleep(20000);
                                    ScriptResult dfResult = JschUtils.executeScriptJsch(instanceById.getPublicIps(), instanceDetails.getUsername(), currentPwd, instanceDetails.getPort(), DF_SCRIPT);
                                    if (dfResult.isSuccess()) {
                                        log.info("DF脚本执行成功");

                                        sendMessage(session, "[救援服务] 开始执行系统初始化....\r\n");
                                        ScriptResult sysInit = JschUtils.executeScriptJsch(instanceById.getPublicIps(), instanceDetails.getUsername(), currentPwd, instanceDetails.getPort(), UPGRADE_AND_INIT_SCRIPT);
                                        if (sysInit.isSuccess()) {
                                            sendMessage(session, "[救援服务] 系统初始化成功！");
                                        }
                                    }

                                    String changePassword = PasswordGenerator.generatePassword();
                                    Thread.sleep(20000);
                                    ScriptResult root = enableRootLogin(instanceById.getPublicIps(), instanceDetails.getUsername(), currentPwd, changePassword, instanceDetails.getPort());
                                    sendMessage(session, "[救援服务] 救援流程已成功结束！");
                                    sendMessage(session, "[登录信息] 以下为登录凭据:\r\n");
                                    sendMessage(session, "👤 IP地址: " + instanceById.getPublicIps() + "\r\n");
                                    sendMessage(session, "👤 用户名: root\r\n");
                                    if (root.isSuccess()) {
                                        currentPwd = changePassword;
                                        sendMessage(session, "🔑 密码: " + currentPwd + "\r\n");
                                        sendMessage(session, "[救援服务] 已经成功救援该实例,后续步骤在后台继续执继续执行,可以登录验证该实例\r\n");
                                        //执行备份
                                        instanceById.setPassword(currentPwd);
                                        instanceDetailsService.doBootVolumeBackUpNoAuthReplace(instanceById, finalUser, sourceBootVolumeId);

                                        if (StringUtils.isNotEmpty(finalDeleteCloneBootVolumeId)) {
                                            sendMessage(session, "[救援服务] 开始清理救援资源...\r\n");
                                            try {
                                                terminateBootVolume(tenant, finalDeleteCloneBootVolumeId);
                                            } catch (Exception e) {
                                                log.warn("terminateBootVolume 引导卷id:{},出现异常", finalDeleteCloneBootVolumeId);
                                            }
                                            sendMessage(session, "[救援服务] 救援资源清理成功...\r\n");
                                        }

                                    } else {
                                        sendMessage(session, "🔑 密码: " + currentPwd + "\r\n");
                                    }


                                    instanceDetails.setPassword(currentPwd);
                                    ociSshConnService.saveOrUpdate(instanceDetails);

                                    sendMessage(session, "[救援服务] 恭喜你,实例已经成功救援,请登录验证,已发送消息\r\n");

                                    //发送消息
                                    messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplate(String.format(MESSAGE_RESCUE_SUCCESS_TEMPLATE, tenant.getUserName(), tenant.getRegion(), instanceById.getDisplayName(), instanceById.getPublicIps(), currentPwd));

                                    sendMessage(session, "[救援服务] 实例已经救援成功,请登录进行验证,清理其他资源中,可忽略...\r\n");
                                    temInstanceService.deleteByTenancyAndRegionAndArchitecture(tenant.getTenancy(), getRegionCode(finalUser.getRegion()), finalArchitecture, provider, finalNewInstanceId, deleteInsFlag);

                                    stopWatch.stop();
                                    // 获取耗时
                                    double totalTimeSeconds = stopWatch.getTotalTimeSeconds();
                                    sendMessage(session, "[救援服务] 实例救援成功,共耗时" + totalTimeSeconds + "...\r\n");
                                    //同步一次实例
                                    tenantService.syncOci(tenant.getId());
                                    closeWebsocket(session);
                                }
                            }
                        } catch (Exception e) {
                            log.error("Error checking rescue status after retries", e);
                            sendMessage(session, "警告: 检查救援状态出错，但救援过程可能仍在进行: " + e.getMessage() + "\r\n");

                            int maxFailures = 10; // 设置最大失败次数
                            int currentFailures = incrementFailureCount(finalNewInstanceId); // 实现一个方法来记录和获取失败次数
                            if (currentFailures >= maxFailures) {
                                log.error("Maximum failure count reached, terminating rescue process");
                                sendError(session, "达到最大失败次数，终止救援流程");
                                completed.set(true);
                            }
                        }
                    }, 5, 5, TimeUnit.SECONDS);

                } catch (Exception e) {
                    log.error("Error in rescue process", e);
                    sendError(session, "救援过程发生错误: " + e.getMessage());
                }
            } catch (Exception e) {
                log.error("Error handling rescue init", e);
                sendError(session, "初始化救援过程失败: " + e.getMessage());
            }
        });
        sessionTasks.put(session.getId(), future);
    }

    public static void attachBootVolumeWithRetry(SimpleAuthenticationDetailsProvider provider,
                                                 String instanceId,
                                                 String bootVolumeId) {
        int maxRetries = 20;
        int retryIntervalSeconds = 10;
        int attempt = 0;

        while (true) {
            try {
                OciUtils.attachBootVolume(provider, instanceId, bootVolumeId);
                log.info("引导卷挂载成功: {}", bootVolumeId);
                break;
            } catch (Exception e) {
                attempt++;
                log.warn("第 {} 次挂载引导卷失败: {}，BootVolumeId: {}", attempt, e.getMessage(), bootVolumeId);

                if (attempt >= maxRetries) {
                    log.error("重试 {} 次后仍然失败，放弃挂载引导卷: {}", maxRetries, bootVolumeId);
                    throw new RuntimeException("引导卷挂载失败", e);
                }

                try {
                    log.info("等待 {} 秒后重试...", retryIntervalSeconds);
                    Thread.sleep(retryIntervalSeconds * 1000L);
                } catch (InterruptedException ie) {
                    Thread.currentThread().interrupt();
                    throw new RuntimeException("重试等待被中断", ie);
                }
            }
        }
    }

    private TmpInstanceResponse createTmpInstance(String oldInstanceId,String earliestBootVolumeId,TemInstance temInstance,String regionCode,WebSocketSession session, Tenant tenant, String helpArchitecture,boolean bootTerminated) {
        //getAlreadyAmdInstance(tenant,session,helpArchitecture,bootTerminated);
        TmpInstanceResponse tmpInstanceResponse = new TmpInstanceResponse();
        //sendMessage(session, "[实例操作] 正在创建救援用临时实例...\r\n");
        try {
            sendMessage(session, "[救援服务] 正在启动救援服务,请耐心等待,大概需要1分钟时间...\r\n");
            User user = bootPojo(tenant, helpArchitecture);
            user.setHelpFlag(2);
            user.setBackUp(1);
            OracleInstanceDetail instanceData = oracleCloudService.createInstanceData(user);
            if (instanceData.getInstance() == null) {
                //sendError(session, "临时实例创建失败，无法继续执行救援流程\r\n");
                sendError(session, "[救援服务] 救援服务启动失败,救援停止..\r\n");
                closeWebsocket(session);
                throw new RuntimeException("救援实例创建失败");
            }

            BootVolume bootVolume = getBootVolume(instanceData.getInstance(), tenant);
            tmpInstanceResponse.setTmpBootVolumeId(bootVolume.getId());
            if (bootTerminated){
                log.debug("原实例的引导卷已经被终止,需要克隆引导卷");
                String cloneBootVolumeId = cloneBootVolumeFromBootVolume(tenant, bootVolume.getId(), System.currentTimeMillis() + "_new", 50L);
                temInstance.setCloneBootVolumeId(cloneBootVolumeId);
            }
            Instance instance = instanceData.getInstance();
            temInstance.setTenancy(tenant.getTenancy());
            temInstance.setRegion(regionCode);
            temInstance.setInstanceId(instanceData.getInstance().getId());
            temInstance.setPublicIp(instanceData.getPublicIp());
            temInstance.setArchitecture(helpArchitecture);
            temInstanceService.save(temInstance);
            String newInstanceId = instance.getId();
            log.debug("实例创建成功,{}",newInstanceId);
            //sendMessage(session, "[临时实例] 临时实例创建成功，ID: " + instanceData.getInstance().getId()+"\r\n");
            tmpInstanceResponse.setUser(user);
            tmpInstanceResponse.setNewInstanceId(newInstanceId);
            tmpInstanceResponse.setCloneBootVolumeId(temInstance.getCloneBootVolumeId());
            tmpInstanceResponse.setInstance(instanceData.getInstance());
            tmpInstanceResponse.setDeleteInsFlag(true);

            InstanceDetails instanceDetails = new InstanceDetails();
            String processorDescription = instance.getShapeConfig().getProcessorDescription();
            String compartmentId = instance.getCompartmentId();
            Float ocpus = instance.getShapeConfig().getOcpus();
            instanceDetails.setInstanceId(instance.getId());
            instanceDetails.setOcpus(ocpus.intValue());
            instanceDetails.setDisplayName(instance.getDisplayName());
            instanceDetails.setShape(instance.getShape());
            instanceDetails.setProcessorDescription(processorDescription);
            instanceDetails.setArchitecture(instanceData.getArchitecture());
            String value = instance.getLifecycleState().getValue();
            instanceDetails.setState(value);
            instanceDetails.setCompartmentId(compartmentId);
            instanceDetails.setTenantId(user.getId());
            instanceDetails.setMemoryInGBs(instance.getShapeConfig().getMemoryInGBs().intValue());

            //引导卷信息
            instanceDetails.setBootVolumeId(bootVolume.getId());
            instanceDetails.setBootVolumeName(bootVolume.getDisplayName());
            instanceDetails.setBootVolumeSizeInGBs(bootVolume.getSizeInGBs());
            instanceDetails.setVpusPerGB(String.valueOf(bootVolume.getVpusPerGB() == null ? 0L : bootVolume.getVpusPerGB()));
            instanceDetails.setPublicIps(instanceData.getPublicIp());
            instanceDetails.setPrivateIps(instanceData.getPrivateIp());
            //保存开机密码
            instanceDetails.setUsername("root");
            instanceDetails.setPort(22);
            instanceDetails.setPassword(user.getRootPassword());
            instanceDetails.setAvailabilityDomain(instance.getAvailabilityDomain());
            tmpInstanceResponse.setInstanceDetails(instanceDetails);
            //需要执行一次连接,必须连接成功才可以执行
            boolean b = JschUtils.tryConnectWithRetry(instanceDetails.getPublicIps(), instanceDetails.getUsername(), instanceDetails.getPassword(), instanceDetails.getPort());
            if (!b){
                sendError(session, "[救援服务] 救援服务启动失败,救援停止..\r\n");
                closeWebsocket(session);
                throw new RuntimeException("救援实例创建失败");
            }
            //不用再备份了
            //delayedTaskExecutor.schedule(() ->{eventPublisher.publishEvent(new InstanceBackUpEvent(this, instanceData));}, 3, TimeUnit.MINUTES);
            sendMessage(session, "[救援服务] 服务启动成功...\r\n");
        } catch (Exception e) {
            //实例创建失败,将之前分离的引导卷执行恢复
            SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
            OciUtils.attachBootVolume(provider, oldInstanceId, earliestBootVolumeId);
            sendError(session, "[救援服务] 救援服务启动失败,救援停止,实例已经恢复成救援前状态..\r\n");
            closeWebsocket(session);
            throw new RuntimeException("救援实例创建失败");
        }
        return tmpInstanceResponse;
    }

    private boolean doHelpFromBootVolumeBackup(WebSocketSession session,String oldBootVolumeId,Tenant tenant,
                                            InstanceDetails instanceById,
                                            BootVolumeBackup homeRegionBackUpVolume,
                                            String sourceRegionCode,
                                            Tenant parentTenant) {
        boolean connect = false;
        try {
            final String architecture = instanceById.getArchitecture();
            String availabilityDomain = instanceById.getAvailabilityDomain();
            if (StringUtils.isEmpty(availabilityDomain)){
                 availabilityDomain = getAvailabilityDomainByInstanceId(tenant, instanceById.getInstanceId());
            }
            //第一步:终止引导卷
            boolean b = terminateBootVolume(tenant, oldBootVolumeId);
            if (!b){
                log.debug("引导卷终止出现异常");
                return connect;
            }

            //第二步骤:从备份创建引导卷(需要救援机器的同一个可用性域)
            String regionCode = getRegionCode(tenant.getRegion());
            String bootVolumeFromBackup;
            //判断跨区域备份
            if (StringUtils.isNotBlank(sourceRegionCode) && !regionCode.equals(sourceRegionCode)){
                //救援的实例和备份卷不在同一个区域
                //第一步:复制
                String s = OciBackUpUtils.copyBootVolumeBackupToRegion(tenant, homeRegionBackUpVolume.getId(), sourceRegionCode, regionCode, architecture);
                //第二步: 从备份创建
                bootVolumeFromBackup = createBootVolumeFromBackup(tenant, regionCode, s, availabilityDomain);
            }else{
                bootVolumeFromBackup = createBootVolumeFromBackup(tenant, regionCode, homeRegionBackUpVolume.getId(), availabilityDomain);
            }

            if (null == bootVolumeFromBackup){
                log.debug("从备份创建引导卷出现异常");
                return connect;
            }


            //第三步:将引导卷挂载到实例
            //sendMessage(session, "[引导卷操作] 正在将修复后的引导卷重新挂载到原实例...\r\n");
            SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
            OciUtils.attachBootVolume(provider, instanceById.getInstanceId(), bootVolumeFromBackup);
            //sendMessage(session, "[引导卷操作] 引导卷已成功重新挂载到原实例\r\n");


            // 第四步:重新引导救援实例
            sendMessage(session, "[救援服务] 正在重新启动实例...\r\n");
            //OciUtils.startInstance(provider, instanceById.getInstanceId());
            OciUtils.resetInstance(tenant, instanceById.getInstanceId());
            sendMessage(session, "[救援服务] 实例启动成功...\r\n");


            //重新同步实例
            sendMessage(session, "[救援服务] 开始执行实例初始化任务...\r\n");
            tenantService.syncOci(tenant.getId());
            sendMessage(session, "[救援服务] 实例初始化任务成功...\r\n");

            //第五步:获取密码
            InstanceDetails instanceDetails = null;
            String jsonInstanceDetail = OciObjectStorageUtil.downloadJsonString(parentTenant, OciObjectStorageUtil.OBJECT_NAME_PATH_PREFIX + architecture);
            if (null != jsonInstanceDetail) {
                instanceDetails = JSONUtil.toBean(jsonInstanceDetail, InstanceDetails.class);
            }else{
                instanceDetails = new InstanceDetails();
                instanceDetails.setPublicIps(instanceById.getPublicIps());
                instanceDetails.setPassword(DEFAULT_PASSWD);
                instanceDetails.setUsername("root");
                instanceDetails.setPort(22);
            }

            if (!PingUtil.ping(instanceById.getPublicIps()).isReachable()){
                log.debug("当前ip无法ping通,执行协议开启后再次尝试");
                securityRuleService.checkAndEnableRule(tenant);
            }

            //ssh连接检测
            Thread.sleep(10000);
            sendMessage(session, "[救援服务] 开始执行实例连接检测...\r\n");
            boolean sshConFlag = verifyPasswordChange(instanceById.getPublicIps(), instanceDetails.getPassword());
            String password = instanceDetails.getPassword();
            if (sshConFlag){
                sendMessage(session, "[救援服务] 实例连接检测成功...\r\n");
                sendMessage(session, "[救援服务] 救援流程已成功！");
                sendMessage(session, "[登录信息] 请使用以下凭据连接实例:\r\n");
                sendMessage(session, "👤 IP地址: "+instanceById.getPublicIps()+"\r\n");
                sendMessage(session, "👤 用户名: root\r\n");
                sendMessage(session, "🔑 密  码: "+ password+"\r\n");

                sendMessage(session, "[说明]如果密码不正确,请使用系统初始密码: "+HELP_INIT_PASSWORD+"进行登录验证\r\n");
                //sendMessage(session, "[说明]特此感谢此次救援镜像,脚本地址: "+"https://raw.githubusercontent.com/leitbogioro/Tools/master/Linux_reinstall/InstallNET.sh\r\n");

                instanceDetails.setPublicIps(instanceById.getPublicIps());
                instanceDetails.setPassword(password);
                instanceDetails.setUsername("root");
                instanceDetails.setPort(22);
                instanceDetails.setInstanceId(instanceById.getInstanceId());
                ociSshConnService.saveOrUpdate(instanceDetails);

                //发送消息
                messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplate(String.format(MESSAGE_RESCUE_SUCCESS_TEMPLATE,tenant.getUserName(),regionCode,instanceById.getDisplayName(),instanceById.getPublicIps(),password));
                connect = true;
            }else {
                //使用初始密码再连接一次
                String currPass = PasswordGenerator.generatePassword();
                ScriptResult root = changeRootPassword(instanceById.getPublicIps(), "root", HELP_INIT_PASSWORD, currPass);
                if (root.isSuccess()){
                    password = currPass;
                    sendMessage(session, "[救援服务] 实例连接检测成功...\r\n");
                    sendMessage(session, "[救援服务] 救援流程已成功！");
                    sendMessage(session, "[登录信息] 请使用以下凭据连接实例:\r\n");
                    sendMessage(session, "👤 IP地址: "+instanceById.getPublicIps()+"\r\n");
                    sendMessage(session, "👤 用户名: root\r\n");
                    sendMessage(session, "🔑 密  码: "+ password+"\r\n");

                    sendMessage(session, "[说明]如果密码不正确,请使用系统初始密码: "+HELP_INIT_PASSWORD+"进行登录验证\r\n");

                    instanceDetails.setPublicIps(instanceById.getPublicIps());
                    instanceDetails.setPassword(password);
                    instanceDetails.setUsername("root");
                    instanceDetails.setPort(22);
                    instanceDetails.setInstanceId(instanceById.getInstanceId());
                    ociSshConnService.saveOrUpdate(instanceDetails);

                    //发送消息
                    messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplate(String.format(MESSAGE_RESCUE_SUCCESS_TEMPLATE,tenant.getUserName(),regionCode,instanceById.getDisplayName(),instanceById.getPublicIps(),password));
                    connect = true;
                }else{
                    OciUtils.stopInstance(provider, instanceById.getInstanceId());
                    //卸载挂载的引导卷,并删除引导卷,
                    String bootVolumeId = OciUtils.detachBootVolume(provider, instanceById.getInstanceId());
                    deleteBootVolume(tenant, bootVolumeId);
                }
                /*else{
                    *//*OciBackUpUtils.deleteBootVolumeBackup(tenant, homeRegionBackUpVolume.getId());
                    //删除存储桶
                    String objectName = OBJECT_NAME_PATH_PREFIX + architecture;
                    deleteObject(tenant, objectName);*//*
                    sendError(session, "[救援服务] 实例连接检测失败,请自行执行登录验证,如无法连接,请重试...\r\n");
                }*/
            }
        } catch (Exception e) {
            log.warn("doHelpFromBootVolumeBackup 出现异常");
            sendError(session, "[救援服务] 救援失败,系统再次尝试救援...\r\n");
            //closeWebsocket(session);
        }
        return connect;
    }


    private void doHelpFromBootVolumeOtherBackup(WebSocketSession session,String oldBootVolumeId,Tenant tenant, InstanceDetails instanceById, BootVolumeBackup homeRegionBackUpVolume,String availabilityDomain) {
        try {
            //第一步:终止引导卷
            boolean b = terminateBootVolume(tenant, oldBootVolumeId);
            if (!b){
                log.debug("引导卷终止出现异常");
                sendError(session, "实例救援失败,救援进程结束");
                return;
            }

            //第二步骤:从备份创建引导卷(需要救援机器的同一个可用性域)
            String regionCode = getRegionCode(tenant.getRegion());
            String bootVolumeFromBackup = createBootVolumeFromBackup(tenant, regionCode, homeRegionBackUpVolume.getId(), availabilityDomain);
            if (null == bootVolumeFromBackup){
                log.debug("从备份创建引导卷出现异常");
                sendError(session, "实例救援失败,救援进程结束");
                throw new RuntimeException("实例救援失败,救援进程结束");
            }

            //第三步:将引导卷挂载到实例
            SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
            OciUtils.attachBootVolume(provider, instanceById.getInstanceId(), bootVolumeFromBackup);
        } catch (Exception e) {
            log.warn("doHelpFromBootVolumeBackup 出现异常");
            sendError(session, "[救援服务] 救援失败,救援停止..\r\n");
            closeWebsocket(session);
            throw new RuntimeException("实例救援失败,救援进程结束");
        }
    }

    private BootVolumeBackup getHomeRegionBackUpVolume(Tenant tenantChild, InstanceDetails instanceById) {
        String tenantId = tenantChild.getTenantId();
        Tenant tenant = null;
        if (tenantChild.getIsHomeRegion()){
            tenant = tenantChild;
        }else{
            tenant = tenantRepository.findParentByChildTenantId(tenantId);
        }
        return OciBackUpUtils.hasBootVolumeBackup(tenant, instanceById.getArchitecture());
    }

    private void closeWebsocket(WebSocketSession session) {
        if (session.isOpen()){
            try {
                session.close();
            } catch (IOException e) {
                log.warn("回话关闭失败");
            }
        }
    }


    private int incrementFailureCount(String instanceId) {
        AtomicInteger counter = failureCountMap.computeIfAbsent(instanceId, k -> new AtomicInteger(0));
        return counter.incrementAndGet();
    }

    private void resetFailureCount(String instanceId) {
        failureCountMap.remove(instanceId);
    }
    /**
     * 发送格式化消息给前端
     * 消息格式更专业，包含时间戳、操作类型和详细信息
     */
    private void sendMessage(WebSocketSession session, String message) {
        synchronized (messageLock) {
            try {
                if (!session.isOpen()) {
                    log.warn("Session is closed, cannot send message");
                    return;
                }

                // 获取当前时间戳
                String timestamp = java.time.LocalDateTime.now().format(java.time.format.DateTimeFormatter.ofPattern("HH:mm:ss"));

                // 解析消息类型
                String messageType = "INFO";
                String formattedMessage = message;

                // 根据消息内容确定消息类型和格式化消息
                if (message.contains("成功")) {
                    messageType = "SUCCESS";
                    formattedMessage = "✅ " + message;
                } else if (message.contains("失败") || message.contains("错误")) {
                    messageType = "ERROR";
                    formattedMessage = "❌ " + message;
                } else if (message.contains("开始") || message.contains("正在")) {
                    messageType = "PROCESS";
                    formattedMessage = "⏳ " + message;
                } else if (message.contains("完成")) {
                    messageType = "COMPLETE";
                    formattedMessage = "✓ " + message;
                }

                Map<String, Object> response = new HashMap<>();
                response.put("type", "output");
                response.put("messageType", messageType);
                response.put("timestamp", timestamp);
                response.put("data", formattedMessage);

                String jsonMessage = objectMapper.writeValueAsString(response);
                session.sendMessage(new TextMessage(jsonMessage));

                log.debug("Message sent successfully: {}", message);
            } catch (IOException | IllegalStateException e) {
                log.error("Failed to send message", e);
            }
        }
    }

    /**
     * 发送错误消息给前端
     * 错误消息格式更详细，包含错误代码和时间戳
     */
    private void sendError(WebSocketSession session, String error) {
        Object lock = sessionLocks.getOrDefault(session.getId(), new Object());
        synchronized (lock) {
            try {
                // 获取当前时间戳
                String timestamp = java.time.LocalDateTime.now().format(java.time.format.DateTimeFormatter.ofPattern("HH:mm:ss"));

                Map<String, Object> response = new HashMap<>();
                response.put("type", "error");
                response.put("timestamp", timestamp);
                response.put("errorCode", "RESCUE_ERR");
                response.put("message", "❌ 错误: " + error);

                String jsonMessage = objectMapper.writeValueAsString(response);
                log.warn("Sending error JSON: {}", jsonMessage);

                if (session.isOpen()) {
                    TextMessage textMessage = new TextMessage(jsonMessage);
                    session.sendMessage(textMessage);
                    log.warn("Error message sent, length: {}", textMessage.getPayloadLength());
                    closeWebsocket(session);
                } else {
                    log.warn("Session is closed, cannot send error message");
                }
            } catch (IOException e) {
                log.error("Error sending error message to WebSocket", e);
            }
        }
    }

    @Override
    public void afterConnectionClosed(WebSocketSession session, CloseStatus status) {
        String sessionId = session.getId();
        // 中断救援线程
        Future<?> future = sessionTasks.remove(sessionId);
        if (future != null && !future.isDone()) {
            future.cancel(true);
        }

        // 移除会话锁
        sessionLocks.remove(sessionId);

        log.info("Rescue WebSocket connection closed: {}", sessionId);
    }

    @PreDestroy
    public void destroy() {
        executorService.shutdownNow();
        scheduledExecutorService.shutdownNow();
        heartbeatExecutor.shutdownNow();

        try {
            executorService.awaitTermination(5, TimeUnit.SECONDS);
            scheduledExecutorService.awaitTermination(5, TimeUnit.SECONDS);
            heartbeatExecutor.awaitTermination(5, TimeUnit.SECONDS);
        } catch (InterruptedException e) {
            log.error("Error shutting down executor services", e);
        }
    }


    public TmpInstanceResponse getAlreadyAmdInstance(String sourceInstanceId,Tenant tenant,WebSocketSession session,String helpArchitectures,boolean bootTerminated){
        //需要同步一次实例
        tenantService.syncOci(tenant.getId());
        //查询是否存在amd实例,存在直接获取密码
        TmpInstanceResponse tmpInstanceResponse = new TmpInstanceResponse();
        TemInstance temInstance = null;
        Page<InstanceDetailsRes> allInstances = oracleInstanceService.getAllInstances(0, 10, String.valueOf(tenant.getId()));
        if (null != allInstances){
            List<InstanceDetailsRes> content = allInstances.getContent();
            if (!CollectionUtils.isEmpty(content)){
                //过滤掉救援的实例
                /*List<InstanceDetailsRes> collect = content.stream()
                        .filter(instance -> "AMD".equals(instance.getArchitecture()))
                        .collect(Collectors.toList());*/
                for (InstanceDetailsRes amdInstance : content) {
                    final String instanceId = amdInstance.getInstanceId();
                    if (sourceInstanceId.equals(instanceId)){
                        continue;
                    }
                    //校验状态
                        Instance amdInstanceExists = OciUtils.getInstanceById(tenant, amdInstance.getInstanceId());
                        if (null == amdInstanceExists ||
                                amdInstanceExists.getLifecycleState().equals(Instance.LifecycleState.Terminated) ||
                                amdInstanceExists.getLifecycleState().equals(Instance.LifecycleState.Terminating)){
                            continue;
                        }
                        //获取密码
                        Optional<CloudSshConn> byInstanceId = cloudSshConnRepository.findByInstanceId(amdInstance.getInstanceId());
                        if (byInstanceId.isPresent()){
                            CloudSshConn cloudSshConn = byInstanceId.get();
                            boolean sshConFlag = verifyPasswordChange(amdInstance.getPublicIps(), cloudSshConn.getPassword());
                            if (sshConFlag){
                                log.debug("存在的实例连接成功");
                                temInstance = new TemInstance();
                                User user = bootPojo(tenant, amdInstance.getArchitecture());
                                Instance instance = getInstanceById(tenant, amdInstance.getInstanceId());
                                BootVolume bootVolume = getBootVolume(instance, tenant);
                                if (bootTerminated){
                                    log.debug("原实例的引导卷已经被终止,需要克隆引导卷");
                                    String cloneBootVolumeId = cloneBootVolumeFromBootVolume(tenant, bootVolume.getId(), System.currentTimeMillis() + "_new", 50L);
                                    temInstance.setCloneBootVolumeId(cloneBootVolumeId);
                                }
                                temInstance.setTenancy(tenant.getTenancy());
                                temInstance.setRegion(instance.getRegion());
                                temInstance.setInstanceId(instance.getId());
                                temInstance.setPublicIp(amdInstance.getPublicIps());
                                temInstance.setArchitecture(amdInstance.getArchitecture());
                                //temInstanceService.save(temInstance);
                                String newInstanceId = instance.getId();
                                log.debug("实例创建成功,{}",newInstanceId);
                                //sendMessage(session, "[临时实例] 临时实例创建成功，ID: " + instanceData.getInstance().getId()+"\r\n");
                                tmpInstanceResponse.setUser(user);
                                tmpInstanceResponse.setNewInstanceId(newInstanceId);
                                tmpInstanceResponse.setCloneBootVolumeId(temInstance.getCloneBootVolumeId());
                                tmpInstanceResponse.setInstance(instance);
                                tmpInstanceResponse.setDeleteInsFlag(false);
                                tmpInstanceResponse.setNewInstanceId(newInstanceId);


                                InstanceDetails instanceDetails = new InstanceDetails();
                                String processorDescription = instance.getShapeConfig().getProcessorDescription();
                                String compartmentId = instance.getCompartmentId();
                                Float ocpus = instance.getShapeConfig().getOcpus();
                                instanceDetails.setInstanceId(instance.getId());
                                instanceDetails.setOcpus(ocpus.intValue());
                                instanceDetails.setDisplayName(instance.getDisplayName());
                                instanceDetails.setShape(instance.getShape());
                                instanceDetails.setProcessorDescription(processorDescription);
                                instanceDetails.setArchitecture(amdInstance.getArchitecture());
                                String value = instance.getLifecycleState().getValue();
                                instanceDetails.setState(value);
                                instanceDetails.setCompartmentId(compartmentId);
                                instanceDetails.setTenantId(user.getId());
                                instanceDetails.setMemoryInGBs(instance.getShapeConfig().getMemoryInGBs().intValue());

                                //引导卷信息
                                instanceDetails.setBootVolumeId(bootVolume.getId());
                                instanceDetails.setBootVolumeName(bootVolume.getDisplayName());
                                instanceDetails.setBootVolumeSizeInGBs(bootVolume.getSizeInGBs());
                                instanceDetails.setVpusPerGB(String.valueOf(bootVolume.getVpusPerGB() == null ? 0L : bootVolume.getVpusPerGB()));
                                instanceDetails.setPublicIps(amdInstance.getPublicIps());
                                instanceDetails.setPrivateIps(amdInstance.getPrivateIps());
                                //保存开机密码
                                instanceDetails.setUsername("root");
                                instanceDetails.setPort(22);
                                instanceDetails.setPassword(cloudSshConn.getPassword());
                                instanceDetails.setAvailabilityDomain(instance.getAvailabilityDomain());
                                tmpInstanceResponse.setInstanceDetails(instanceDetails);

                                ScriptResult root = enableRootLogin(instanceDetails.getPublicIps(), "root", instanceDetails.getPassword(), instanceDetails.getPassword(), 22);
                                if (root.isSuccess()){
                                    log.debug("已经存在实例 root用户登录成功");
                                    instanceDetailsService.doBootVolumeBackUpNoAuth(instanceDetails, user, bootVolume.getId());
                                }else {
                                    log.debug("root用户登录失败");
                                }

                                sendMessage(session, "[救援服务] 服务启动成功...\r\n");
                                return tmpInstanceResponse;
                            }else{
                                sendError(session, "[救援服务] 检测到存在实例:"+amdInstance.getPublicIps()+"无法执行连接,本次救援需要借助此实例,请点击实例列表的ssh连接功能配置密码后继续..\r\n");
                                closeWebsocket(session);
                                throw new RuntimeException("救援实例连接失败");
                            }
                        }
                }
            }
        }
        return null;
    }
}
