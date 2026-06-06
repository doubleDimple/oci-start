package com.doubledimple.ociserver.service.oracle;

import com.alibaba.fastjson2.JSON;
import com.doubledimple.dao.entity.BootInstance;
import com.doubledimple.dao.entity.OciComputerInfo;
import com.doubledimple.dao.entity.OpenBootLock;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.BootInstanceRepository;
import com.doubledimple.dao.repository.OciComputerInfoRepository;
import com.doubledimple.dao.repository.OpenBootLockRepository;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.ociserver.config.annotations.UseSocksProxy;
import com.doubledimple.ociserver.config.constant.SystemScriptShell;
import com.doubledimple.ociserver.config.ProxyContext;
import com.doubledimple.ociserver.config.event.OracleInstanceSuccessEvent;
import com.doubledimple.ociserver.config.OciLogBuilder;
import com.doubledimple.ociserver.pojo.domain.dto.OracleInstanceDetail;
import com.doubledimple.ociserver.pojo.domain.dto.User;
import com.doubledimple.ociserver.pojo.dto.OciComputerDto;
import com.doubledimple.ociserver.pojo.dto.OciGatewayVcnPair;
import com.doubledimple.ociserver.pojo.enums.ArchitectureEnum;
import com.doubledimple.ociserver.pojo.enums.OperationSystemEnum;
import com.doubledimple.ociserver.config.exception.OciExceptionFactory;
import com.doubledimple.ociserver.service.BootTotalInstanceService;
import com.doubledimple.ociserver.service.OpenSuccessService;
import com.doubledimple.ociserver.utils.oracle.OciComputerUtils;
import com.doubledimple.ociserver.utils.oracle.OciUtils;
import com.oracle.bmc.ClientConfiguration;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.core.BlockstorageClient;
import com.oracle.bmc.core.ComputeClient;
import com.oracle.bmc.core.ComputeWaiters;
import com.oracle.bmc.core.VirtualNetworkClient;

import com.oracle.bmc.core.model.*;
import com.oracle.bmc.core.requests.*;
import com.oracle.bmc.core.responses.*;
import com.oracle.bmc.http.client.jersey.JerseyHttpProvider;
import com.oracle.bmc.identity.IdentityClient;
import com.oracle.bmc.identity.model.AvailabilityDomain;
import com.oracle.bmc.identity.model.Compartment;
import com.oracle.bmc.identity.requests.ListAvailabilityDomainsRequest;
import com.oracle.bmc.identity.requests.ListCompartmentsRequest;
import com.oracle.bmc.identity.responses.ListAvailabilityDomainsResponse;
import com.oracle.bmc.identity.responses.ListCompartmentsResponse;
import com.oracle.bmc.model.BmcException;
import com.oracle.bmc.workrequests.WorkRequestClient;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;
import org.springframework.util.CollectionUtils;

import javax.annotation.Resource;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.Function;
import java.util.stream.Collectors;

import static com.doubledimple.ociserver.config.constant.SystemScriptShell.*;
import static com.doubledimple.ociserver.config.exception.ErrorCode.*;
import static com.doubledimple.ociserver.utils.oracle.OciCliUtils.createVcn;
import static com.doubledimple.ociserver.utils.oracle.OciCliUtils.createVcnAndFlowLogs;
import static com.doubledimple.ociserver.utils.oracle.OciUtils.checkShapes;
import static com.doubledimple.ociserver.utils.oracle.OciUtils.getProvider;

/**
 * @author doubleDimple
 * @date 2024:09:21日 08:47
 */
@Service
@Slf4j
public class OracleCloudService {

    private static final JerseyHttpProvider HTTP_PROVIDER = JerseyHttpProvider.getInstance();


    @Resource
    private BootTotalInstanceService bootTotalInstanceService;

    @Resource
    OpenSuccessService openSuccessService;

    @Resource
    private BootInstanceRepository bootInstanceRepository;

    @Resource
    private TenantRepository tenantRepository;

    @Resource
    private OciComputerInfoRepository ociComputerInfoRepository;

    @Resource
    private OciLogBuilder ociLogBuilder;

    @Resource
    private OpenBootLockRepository lockRepo;

    @Resource
    private ApplicationEventPublisher eventPublisher;

    private final ConcurrentHashMap<String, Boolean> RUNNING_TASKS = new ConcurrentHashMap<>();

    @UseSocksProxy
    public OracleInstanceDetail createInstanceData(User user) throws Exception {
        OracleInstanceDetail oracleInstanceDetail = new OracleInstanceDetail();
        oracleInstanceDetail.setUser(user);
        long count = 1L;
        try {
            count = bootTotalInstanceService.inc(user);
            oracleInstanceDetail.setAddCount(count);
        } catch (Exception e) {
            log.warn("统计抢机次数出现异常....");
        }

        //先查询是否存在库里的预创建实例数据
        Long bootId = user.getBootId();
        long tenantId = user.getId();
        Tenant tenant = tenantRepository.findById(tenantId).orElseThrow(() -> OciExceptionFactory.createException(DEF_ERROR_NO_TENANT_ID));
        Optional<BootInstance> byId = bootInstanceRepository.findById(bootId);
        if (byId.isPresent()){
            BootInstance bootInstance = byId.get();
            Optional<OciComputerInfo> ociComputerInfoOpt = ociComputerInfoRepository.findByBootIdStr(bootInstance.getBootId());
            if (ociComputerInfoOpt.isPresent()){
                createFromDbCreateComputer(count,tenant,user,oracleInstanceDetail,ociComputerInfoOpt.get());
            }else{
                createFromOciCreateComputer(count,tenant,user,oracleInstanceDetail);
            }
        }else{
            createFromOciCreateComputer(count,tenant,user,oracleInstanceDetail);
        }
        return oracleInstanceDetail;
    }

    /**
    * @Description: 直接执行创建
    * @Param: [long, com.doubledimple.dao.entity.Tenant, com.doubledimple.ociserver.pojo.domain.dto.User, com.doubledimple.ociserver.pojo.domain.dto.OracleInstanceDetail]
    * @return: com.doubledimple.ociserver.pojo.domain.dto.OracleInstanceDetail
    * @Author: doubleDimple
    * @Date: 10/29/25 3:30 PM
    */
    private OracleInstanceDetail createFromOciCreateComputer(long count,Tenant tenant,User user,OracleInstanceDetail oracleInstanceDetail) {
        SimpleAuthenticationDetailsProvider authenticationDetailsProvider = OciUtils.getProvider(tenant);
        boolean instanceCreated = false; // 添加标记表示实例是否已成功创建
        try(IdentityClient identityClient = IdentityClient.builder()
                .clientConfigurator(ProxyContext.get())
                .httpProvider(HTTP_PROVIDER)
                .build(authenticationDetailsProvider);
            ComputeClient computeClient = ComputeClient.builder()
                    .clientConfigurator(ProxyContext.get())
                    .httpProvider(HTTP_PROVIDER)
                    .build(authenticationDetailsProvider);
            WorkRequestClient workRequestClient = WorkRequestClient.builder()
                    .clientConfigurator(ProxyContext.get())
                    .httpProvider(HTTP_PROVIDER)
                    .build(authenticationDetailsProvider);
            VirtualNetworkClient virtualNetworkClient = VirtualNetworkClient.builder()
                    .clientConfigurator(ProxyContext.get())
                    .httpProvider(HTTP_PROVIDER)
                    .configuration(ClientConfiguration.builder().build())
                    .build(authenticationDetailsProvider);
            BlockstorageClient blockstorageClient = BlockstorageClient.builder()
                    .clientConfigurator(ProxyContext.get())
                    .httpProvider(HTTP_PROVIDER)
                    .build(authenticationDetailsProvider)
        ) {

            identityClient.setRegion(user.getRegion());
            computeClient.setRegion(user.getRegion());
            workRequestClient.setRegion(user.getRegion());
            ComputeWaiters computeWaiters = computeClient.newWaiters(workRequestClient);
            virtualNetworkClient.setRegion(user.getRegion());
            blockstorageClient.setRegion(user.getRegion());

            String compartmentId = findRootCompartment(identityClient, authenticationDetailsProvider.getTenantId());

            List<AvailabilityDomain> availabilityDomains = null;
            try {
                availabilityDomains = getAvailabilityDomains(identityClient, compartmentId);
                if (!checkShapes(computeClient,authenticationDetailsProvider,availabilityDomains)){
                    log.warn("当前租户:{}所有可用性域都不存在shapes,请检查账号是否已经风控", authenticationDetailsProvider.getTenantId());
                    ociLogBuilder.doStopInstance(user.getBootId(),NOT_AUTH.getMessage());
                    OciExceptionFactory.createException(NOT_AUTH);
                }
            } catch (Exception e) {
                throw new RuntimeException(e);
            }
            int size = availabilityDomains.size();
            String kmsKeyId = null;
            InternetGateway internetGateway = null;
            Subnet subnet = null;
            NetworkSecurityGroup networkSecurityGroup = null;
            LaunchInstanceDetails launchInstanceDetails = null;
            Instance instance = null;
            //Instance instanceFromBootVolume = null;
            BootVolume bootVolume = null;

            for (AvailabilityDomain availablityDomain : availabilityDomains) {
                if (instanceCreated){
                    //todo 这里有可能卡bug
                    return oracleInstanceDetail;
                }
                try {
                    List<Shape> shapes = getShape(computeClient, compartmentId, availablityDomain, user);
                    if (shapes.size() == 0) {
                        log.warn("用户:[{}] 的当前可用性域:{} 没有符合的Shape,切换后再次执行", user.getUserName(),availablityDomain.getName());
                        continue;
                    }
                    size --;
                    for (Shape shape : shapes) {
                        Shape.BillingType billingType = shape.getBillingType();
                        Image image = getImage(computeClient, compartmentId, shape, user);
                        if (image == null){
                            log.warn("用户:[{}] 的当前可用性域:{} 没有镜像,切换后再次执行", user.getUserName(),availablityDomain.getName());
                            continue;
                        }
                        String imageId = image.getId();

                        //String networkCidrBlock = getCidr(virtualNetworkClient, compartmentId);
                        List<Vcn> vcns = createVcn(virtualNetworkClient, compartmentId);
                        OciGatewayVcnPair internetGatewayPair = createInternetGateway(virtualNetworkClient, compartmentId, vcns);
                        internetGateway = internetGatewayPair.getInternetGateway();
                        Vcn vcn = internetGatewayPair.getVcn();
                        String networkCidrBlock = vcn.getCidrBlock();
                        addInternetGatewayToDefaultRouteTable(virtualNetworkClient, vcn, internetGateway);

                        subnet = createSubnet(virtualNetworkClient, compartmentId, availablityDomain, networkCidrBlock, vcn);
                        if (null == subnet) {
                            continue;
                        }
                        networkSecurityGroup =
                                createNetworkSecurityGroup(virtualNetworkClient, compartmentId, vcn);
                        addNetworkSecurityGroupSecurityRules(
                                virtualNetworkClient, networkSecurityGroup, networkCidrBlock);

                        if (log.isDebugEnabled()){
                            log.info("current user:[{}] and region:[{}] Instance is being created via image and KMS key ...", user.getUserName(), user.getRegion());
                        }

                        String cloudInitScript = SystemScriptShell.getShell(user.getRootPassword());
                        launchInstanceDetails = createLaunchInstanceDetails(
                                compartmentId, availablityDomain,
                                shape, imageId,
                                subnet, networkSecurityGroup,
                                cloudInitScript, user);
                        try {
                            instance = createInstance(computeClient,user,computeWaiters, launchInstanceDetails);
                        } catch (Exception e) {
                            ociLogBuilder.buildOpenBootException(count,availablityDomain.getName(),size,user,instanceCreated,e,oracleInstanceDetail);
                            continue;
                        }
                        instanceCreated = true;
                        printInstance(user,computeClient, virtualNetworkClient, instance, oracleInstanceDetail,billingType,authenticationDetailsProvider);
                    }
                } catch (Exception e) {
                    return ociLogBuilder.buildOpenBootException(count,availablityDomain.getName(),size,user,instanceCreated,e,oracleInstanceDetail);
                }
            }
        }
        return oracleInstanceDetail;
    }

    //从数据库执行实例的预创建
    private void createFromDbCreateComputer(long count,Tenant tenant,User user,OracleInstanceDetail oracleInstanceDetail,OciComputerInfo ociComputerInfo) {
         boolean instanceCreated = false;
         int size = 0;
         String availabilityDomain = StringUtils.EMPTY;
         SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
         String computerCreateJson = ociComputerInfo.getComputerCreateJson();
         OciComputerDto ociComputerDto = JSON.parseObject(computerCreateJson, OciComputerDto.class);
         Shape.BillingType billingType = ociComputerDto.getBillingType();
         List<LaunchInstanceDetails> dbInstanceDetails = OciComputerUtils.createDbInstanceDetails(ociComputerDto, user);
         try(ComputeClient computeClient = ComputeClient.builder()
                 .clientConfigurator(ProxyContext.get())
                 .httpProvider(HTTP_PROVIDER)
                 .build(provider);
             WorkRequestClient workRequestClient = WorkRequestClient.builder()
                     .clientConfigurator(ProxyContext.get())
                     .httpProvider(HTTP_PROVIDER)
                     .build(provider);
             VirtualNetworkClient virtualNetworkClient = VirtualNetworkClient.builder()
                     .clientConfigurator(ProxyContext.get())
                     .httpProvider(HTTP_PROVIDER)
                     .configuration(ClientConfiguration.builder().build())
                     .build(provider)){
             size = dbInstanceDetails.size();
             ComputeWaiters computeWaiters = computeClient.newWaiters(workRequestClient);
             for (LaunchInstanceDetails launchInstanceDetails : dbInstanceDetails) {
                 size --;
                 availabilityDomain = launchInstanceDetails.getAvailabilityDomain();
                 Instance instance = null;
                 try {
                     instance = createInstance(computeClient,user,computeWaiters, launchInstanceDetails);
                 } catch (Exception e) {
                     ociLogBuilder.buildOpenBootException(count,availabilityDomain,size,user,instanceCreated,e,oracleInstanceDetail);
                     continue;
                 }
                 instanceCreated = true;
                 printInstance(user,computeClient, virtualNetworkClient, instance, oracleInstanceDetail,billingType,provider);
             }
         }catch (Exception e){
             ociLogBuilder.buildOpenBootException(count,availabilityDomain,size,user,instanceCreated,e,oracleInstanceDetail);
         }
    }

    public static List<AvailabilityDomain> getAvailabilityDomains(
            IdentityClient identityClient, String compartmentId) throws Exception {
        ListAvailabilityDomainsResponse listAvailabilityDomainsResponse =
                identityClient.listAvailabilityDomains(ListAvailabilityDomainsRequest.builder()
                        .compartmentId(compartmentId)
                        .build());
        return listAvailabilityDomainsResponse.getItems();
    }

    public static List<Shape> getShape(
            ComputeClient computeClient,
            String compartmentId,
            AvailabilityDomain availabilityDomain,
            User user) {
        List<Shape> shapesNewList = new ArrayList<>();
        ListShapesRequest listShapesRequest =
                ListShapesRequest.builder()
                        .availabilityDomain(availabilityDomain.getName())
                        .compartmentId(compartmentId)
                        .build();
        ListShapesResponse listShapesResponse = computeClient.listShapes(listShapesRequest);
        List<Shape> shapes = listShapesResponse.getItems();
        log.debug("shapes: {}", JSON.toJSONString(shapes));
        if (shapes.isEmpty()) {
            log.warn("{} current shape is not fund",availabilityDomain.getName());
            return shapesNewList;
        }
        List<Shape> vmShapes =
                shapes.stream()
                        .filter(shape -> shape.getShape().startsWith("VM"))
                        .collect(Collectors.toList());
        if (vmShapes.isEmpty()) {
            log.warn("{} current shape {} is not equal prefix VM ",availabilityDomain.getName(),shapes);
            return shapesNewList;
        }
        ArchitectureEnum type = ArchitectureEnum.getType(user.getArchitecture());
        if (type == null) {
            type = ArchitectureEnum.ARM;
        }
        for (Shape vmShape : vmShapes) {
            if (type.getShapeDetail().equals(vmShape.getShape())) {
                shapesNewList.add(vmShape);
            }

            if (log.isDebugEnabled()) {
                log.info("Found Shape: " + vmShape.getShape());
                log.info("Billing Type: " + vmShape.getBillingType());
                log.info("<====================================>");
            }

        }
        return shapesNewList;
    }

    public static Image getImage(ComputeClient computeClient, String compartmentId, Shape shape, User user)
            throws Exception {
        OperationSystemEnum systemType = OperationSystemEnum.getSystemType(user.getOperationSystem());
        ListImagesRequest listImagesRequest =
                ListImagesRequest.builder()
                        .shape(shape.getShape())
                        .compartmentId(compartmentId)
                        .operatingSystem(systemType.getType())
                        .operatingSystemVersion(systemType.getVersion())
                        .build();
        ListImagesResponse response = computeClient.listImages(listImagesRequest);
        List<Image> images = response.getItems();
        if (images.isEmpty()) {
            return null;
        }

        // For demonstration, we just return the first image but for Production code you should have
        // a better
        // way of determining what is needed.
        //
        // Note the latest version of the images for the same operating system is returned firstly.
        Image image = images.get(0);

        return image;
    }

    public static OciGatewayVcnPair createInternetGateway(
            VirtualNetworkClient virtualNetworkClient, String compartmentId, List<Vcn> vcns)
            throws Exception {


        //查询网关是否存在,不存在再创建
        ListInternetGatewaysRequest build = ListInternetGatewaysRequest.builder()
                .compartmentId(compartmentId)
                //.displayName(internetGatewayName)
                .build();

        ListInternetGatewaysResponse listInternetGatewaysResponse = virtualNetworkClient.listInternetGateways(build);
        if (listInternetGatewaysResponse.getItems().size() > 0) {
            OciGatewayVcnPair matchingInternetGateway = findMatchingInternetGateway(listInternetGatewaysResponse.getItems(), vcns);
            if (matchingInternetGateway != null){
                return matchingInternetGateway;
            }
        }

        Vcn vcn = vcns.get(0);
        CreateInternetGatewayDetails createInternetGatewayDetails =
                CreateInternetGatewayDetails.builder()
                        .compartmentId(compartmentId)
                        .displayName(internetGatewayName)
                        .isEnabled(true)
                        .vcnId(vcn.getId())
                        .build();
        CreateInternetGatewayRequest createInternetGatewayRequest =
                CreateInternetGatewayRequest.builder()
                        .createInternetGatewayDetails(createInternetGatewayDetails)
                        .build();
        CreateInternetGatewayResponse createInternetGatewayResponse =
                virtualNetworkClient.createInternetGateway(createInternetGatewayRequest);

        GetInternetGatewayRequest getInternetGatewayRequest =
                GetInternetGatewayRequest.builder()
                        .igId(createInternetGatewayResponse.getInternetGateway().getId())
                        .build();
        GetInternetGatewayResponse getInternetGatewayResponse =
                virtualNetworkClient
                        .getWaiters()
                        .forInternetGateway(
                                getInternetGatewayRequest, InternetGateway.LifecycleState.Available)
                        .execute();
        InternetGateway internetGateway = getInternetGatewayResponse.getInternetGateway();

        log.info("Created Internet Gateway: " + internetGateway.getId());
        OciGatewayVcnPair matchingInternetGateway = new OciGatewayVcnPair(internetGateway, vcn);
        return matchingInternetGateway;
    }

    public static void addInternetGatewayToDefaultRouteTable(
            VirtualNetworkClient virtualNetworkClient, Vcn vcn, InternetGateway internetGateway)
            throws Exception {
        GetRouteTableRequest getRouteTableRequest =
                GetRouteTableRequest.builder().rtId(vcn.getDefaultRouteTableId()).build();
        GetRouteTableResponse getRouteTableResponse =
                virtualNetworkClient.getRouteTable(getRouteTableRequest);

        List<RouteRule> routeRules = getRouteTableResponse.getRouteTable().getRouteRules();

        if (log.isDebugEnabled()) {
            System.out.println("Current Route Rules in Default Route Table");
            System.out.println("==========================================");
            System.out.println();
        }


        // 检查是否已有相同的路由规则
        boolean ruleExists = routeRules.stream()
                .anyMatch(rule -> "0.0.0.0/0".equals(rule.getDestination())
                        && rule.getDestinationType() == RouteRule.DestinationType.CidrBlock);

        if (ruleExists) {
            //log.info("The route rule for destination 0.0.0.0/0 already exists.");
            return; // 退出方法，不添加新的规则
        }

        // 创建新的路由规则
        RouteRule internetAccessRoute =
                RouteRule.builder()
                        .destination("0.0.0.0/0")
                        .destinationType(RouteRule.DestinationType.CidrBlock)
                        .networkEntityId(internetGateway.getId())
                        .build();

        // 将新的规则添加到新的列表中
        List<RouteRule> updatedRouteRules = new ArrayList<>(routeRules);
        updatedRouteRules.add(internetAccessRoute);

        UpdateRouteTableDetails updateRouteTableDetails =
                UpdateRouteTableDetails.builder().routeRules(updatedRouteRules).build();
        UpdateRouteTableRequest updateRouteTableRequest =
                UpdateRouteTableRequest.builder()
                        .updateRouteTableDetails(updateRouteTableDetails)
                        .rtId(vcn.getDefaultRouteTableId())
                        .build();

        virtualNetworkClient.updateRouteTable(updateRouteTableRequest);

        // 等待路由表更新完成
        getRouteTableResponse = virtualNetworkClient
                        .getWaiters()
                        .forRouteTable(getRouteTableRequest, RouteTable.LifecycleState.Available)
                        .execute();
        routeRules = getRouteTableResponse.getRouteTable().getRouteRules();

        if (log.isDebugEnabled()) {
            log.info("Updated Route Rules in Default Route Table");
            log.info("==========================================");
            routeRules.forEach(System.out::println);
        }

    }

    public static Subnet createSubnet(
            VirtualNetworkClient virtualNetworkClient,
            String compartmentId,
            AvailabilityDomain availabilityDomain,
            String networkCidrBlock,
            Vcn vcn)
            throws Exception {

        Subnet subnet = null;
        //检查子网是否存在
        ListSubnetsRequest listRequest = ListSubnetsRequest.builder()
                .compartmentId(compartmentId)
                .vcnId(vcn.getId())
                .build();
        ListSubnetsResponse listResponse = virtualNetworkClient.listSubnets(listRequest);
        List<Subnet> items = listResponse.getItems();
        if (!CollectionUtils.isEmpty(items)) {
            // 如果找到已有的子网，返回其 ID
            for (Subnet item : items) {
                if (!item.getProhibitPublicIpOnVnic()) {
                    log.debug("Found existing public subnet: {}", item.getDisplayName());
                    return item;
                }
            }
        }

        CreateSubnetDetails createSubnetDetails =
                CreateSubnetDetails.builder()
                        .compartmentId(compartmentId)
                        .displayName(subnetName)
                        .cidrBlock(networkCidrBlock)
                        .vcnId(vcn.getId())
                        .routeTableId(vcn.getDefaultRouteTableId())
                        //.dnsLabel("publicsubnet")
                        .build();
        CreateSubnetRequest createSubnetRequest =
                CreateSubnetRequest.builder().createSubnetDetails(createSubnetDetails).build();
        CreateSubnetResponse createSubnetResponse =
                virtualNetworkClient.createSubnet(createSubnetRequest);

        GetSubnetRequest getSubnetRequest =
                GetSubnetRequest.builder()
                        .subnetId(createSubnetResponse.getSubnet().getId())
                        .build();
        GetSubnetResponse getSubnetResponse =
                virtualNetworkClient
                        .getWaiters()
                        .forSubnet(getSubnetRequest, Subnet.LifecycleState.Available)
                        .execute();
        subnet = getSubnetResponse.getSubnet();

        if (log.isDebugEnabled()){
            log.info("Created Subnet: " + subnet.getId());
            log.info("subnet: [{}]", subnet);
            log.info("");
        }

        return subnet;
    }

    private static NetworkSecurityGroup createNetworkSecurityGroup(
            VirtualNetworkClient virtualNetworkClient, String compartmentId, Vcn vcn)
            throws Exception {

        // 获取 NSG 列表
        ListNetworkSecurityGroupsResponse response =
                virtualNetworkClient.listNetworkSecurityGroups(ListNetworkSecurityGroupsRequest.builder()
                .compartmentId(compartmentId).vcnId(vcn.getId()).build());
        if (null != response && response.getItems().size() > 0){
            return response.getItems().get(0);
        }else {
            CreateNetworkSecurityGroupDetails createNetworkSecurityGroupDetails =
                    CreateNetworkSecurityGroupDetails.builder()
                            .compartmentId(compartmentId)
                            .displayName(networkSecurityGroupName)
                            .vcnId(vcn.getId())
                            .build();
            CreateNetworkSecurityGroupRequest createNetworkSecurityGroupRequest =
                    CreateNetworkSecurityGroupRequest.builder()
                            .createNetworkSecurityGroupDetails(createNetworkSecurityGroupDetails)
                            .build();

            ListNetworkSecurityGroupsRequest build = ListNetworkSecurityGroupsRequest.builder().
                    compartmentId(compartmentId).
                    displayName(networkSecurityGroupName).vcnId(vcn.getId()).build();

            ListNetworkSecurityGroupsResponse listNetworkSecurityGroupsResponse = virtualNetworkClient.listNetworkSecurityGroups(build);
            if (listNetworkSecurityGroupsResponse.getItems().size() > 0) {
                return listNetworkSecurityGroupsResponse.getItems().get(0);
            }

            CreateNetworkSecurityGroupResponse createNetworkSecurityGroupResponse =
                    virtualNetworkClient.createNetworkSecurityGroup(createNetworkSecurityGroupRequest);

            GetNetworkSecurityGroupRequest getNetworkSecurityGroupRequest =
                    GetNetworkSecurityGroupRequest.builder()
                            .networkSecurityGroupId(
                                    createNetworkSecurityGroupResponse
                                            .getNetworkSecurityGroup()
                                            .getId()).build();
            GetNetworkSecurityGroupResponse getNetworkSecurityGroupResponse =
                    virtualNetworkClient
                            .getWaiters()
                            .forNetworkSecurityGroup(
                                    getNetworkSecurityGroupRequest,
                                    NetworkSecurityGroup.LifecycleState.Available)
                            .execute();
            NetworkSecurityGroup networkSecurityGroup =
                    getNetworkSecurityGroupResponse.getNetworkSecurityGroup();

            if (log.isDebugEnabled()) {
                System.out.println("Created Network Security Group: " + networkSecurityGroup.getId());
                System.out.println(networkSecurityGroup);
                System.out.println();
            }
            return networkSecurityGroup;
        }
    }

    private static void addNetworkSecurityGroupSecurityRules(
            VirtualNetworkClient virtualNetworkClient,
            NetworkSecurityGroup networkSecurityGroup,
            String networkCidrBlock) {

        ListNetworkSecurityGroupSecurityRulesRequest listNetworkSecurityGroupSecurityRulesRequest =
                ListNetworkSecurityGroupSecurityRulesRequest.builder()
                        .networkSecurityGroupId(networkSecurityGroup.getId())
                        .build();
        ListNetworkSecurityGroupSecurityRulesResponse
                listNetworkSecurityGroupSecurityRulesResponse =
                virtualNetworkClient.listNetworkSecurityGroupSecurityRules(
                        listNetworkSecurityGroupSecurityRulesRequest);
        List<SecurityRule> securityRules = listNetworkSecurityGroupSecurityRulesResponse.getItems();

        if (securityRules.size() > 0){
            return;
        }
        if (log.isDebugEnabled()) {
            log.info("Current Security Rules in Network Security Group");
            log.info("================================================");
            securityRules.forEach(System.out::println);
            System.out.println();
        }

        AddSecurityRuleDetails addSecurityRuleDetails =
                AddSecurityRuleDetails.builder()
                        .description("Incoming HTTP connections")
                        .direction(AddSecurityRuleDetails.Direction.Ingress)
                        .protocol("6")
                        .source(networkCidrBlock)
                        .sourceType(AddSecurityRuleDetails.SourceType.CidrBlock)
                        .tcpOptions(TcpOptions.builder().destinationPortRange(
                                                PortRange.builder().min(80).max(80).build())
                                        .build())
                        .build();
        AddNetworkSecurityGroupSecurityRulesDetails addNetworkSecurityGroupSecurityRulesDetails =
                AddNetworkSecurityGroupSecurityRulesDetails.builder()
                        .securityRules(Arrays.asList(addSecurityRuleDetails))
                        .build();
        AddNetworkSecurityGroupSecurityRulesRequest addNetworkSecurityGroupSecurityRulesRequest =
                AddNetworkSecurityGroupSecurityRulesRequest.builder()
                        .networkSecurityGroupId(networkSecurityGroup.getId())
                        .addNetworkSecurityGroupSecurityRulesDetails(
                                addNetworkSecurityGroupSecurityRulesDetails)
                        .build();
        virtualNetworkClient.addNetworkSecurityGroupSecurityRules(
                addNetworkSecurityGroupSecurityRulesRequest);

        listNetworkSecurityGroupSecurityRulesResponse =
                virtualNetworkClient.listNetworkSecurityGroupSecurityRules(
                        listNetworkSecurityGroupSecurityRulesRequest);
        securityRules = listNetworkSecurityGroupSecurityRulesResponse.getItems();

        if (log.isDebugEnabled()) {
            log.info("Updated Security Rules in Network Security Group");
            log.info("================================================");
            securityRules.forEach(System.out::println);
            System.out.println();
        }

    }

    private static Instance createInstance(User user,
            ComputeWaiters computeWaiters, LaunchInstanceDetails launchInstanceDetails)
            throws Exception {
        LaunchInstanceRequest launchInstanceRequest =
                LaunchInstanceRequest.builder()
                        .launchInstanceDetails(launchInstanceDetails)
                        .build();
        LaunchInstanceResponse launchInstanceResponse =
                computeWaiters.forLaunchInstance(launchInstanceRequest).execute();

        GetInstanceRequest getInstanceRequest =
                GetInstanceRequest.builder()
                        .instanceId(launchInstanceResponse.getInstance().getId())
                        .build();
        GetInstanceResponse getInstanceResponse =
                computeWaiters
                        .forInstance(getInstanceRequest, Instance.LifecycleState.Running)
                        .execute();
        Instance instance = getInstanceResponse.getInstance();

        if (log.isDebugEnabled()){
            log.debug("Launched Instance: " + instance.getId());
            log.debug("instance: "+instance);
            System.out.println();
        }

        return instance;
    }

    public Instance createInstance(ComputeClient computeClient, User user,
                                   ComputeWaiters computeWaiters,
                                   LaunchInstanceDetails launchInstanceDetails) throws Exception {
        String taskId = String.valueOf(user.getBootId());
        OpenBootLock existingLock = lockRepo.findById(taskId).orElse(null);

        //查询一次当前任务的实例是不是已经创建成功了
        /*Instance instanceAlready = recoverInstance(computeClient, user, launchInstanceDetails);
        if (instanceAlready != null) {
            return instanceAlready;
        }*/

        if (existingLock != null) {
            if (OpenBootLock.Status.SUCCESS.name().equals(existingLock.getStatus())) {
                log.debug("任务[{}]已完成，直接跳过执行，返回结果", taskId);
                GetInstanceRequest request = GetInstanceRequest.builder()
                        .instanceId(existingLock.getInstanceId())
                        .build();
                GetInstanceResponse response = computeClient.getInstance(request);
                Instance instance = response.getInstance();
                if (instance != null) return instance;
            }
        }

        try {
            OpenBootLock newLock = new OpenBootLock(taskId, 1, OpenBootLock.Status.PROCESSING.name());
            lockRepo.saveAndFlush(newLock);
        } catch (Exception e) {
            log.warn("任务[{}]抢锁失败(并发或处理中)，停止执行，等待下次调度。", taskId);
            throw new RuntimeException("任务正在执行中");
        }

        String opcRetryToken = generateConfigToken(taskId, launchInstanceDetails);
        try {
            LaunchInstanceRequest launchInstanceRequest =
                    LaunchInstanceRequest.builder()
                            .launchInstanceDetails(launchInstanceDetails)
                            .opcRetryToken(opcRetryToken)
                            .build();

            LaunchInstanceResponse launchInstanceResponse =
                    computeWaiters.forLaunchInstance(launchInstanceRequest).execute();

            GetInstanceRequest getInstanceRequest =
                    GetInstanceRequest.builder()
                            .instanceId(launchInstanceResponse.getInstance().getId())
                            .build();

            GetInstanceResponse getInstanceResponse =
                    computeWaiters
                            .forInstance(getInstanceRequest, Instance.LifecycleState.Running)
                            .execute();
            Instance instance = getInstanceResponse.getInstance();
            if (log.isDebugEnabled()){
                log.debug("Launched Instance: " + instance.getId());
            }
            OpenBootLock successLock = lockRepo.findById(taskId).get();
            successLock.setStatus(OpenBootLock.Status.SUCCESS.name());
            successLock.setInstanceId(instance.getId());
            lockRepo.saveAndFlush(successLock);
            return instance;
        } catch (Exception e) {
            if (e instanceof BmcException) {
                //先看看是否已经创建成功的判断
                Instance recoveredInstance = recoverInstance(computeClient, user, launchInstanceDetails);
                if (recoveredInstance != null) {
                    log.info("检测到实例已经创建成功,直接返回当前实例");
                    return recoveredInstance;
                }
                BmcException bmcEx = (BmcException) e;
                if (bmcEx.getStatusCode() == 400 && "InvalidParameter".equals(bmcEx.getServiceCode())
                        && bmcEx.getMessage().contains("Retry token collision")) {
                    log.warn("检测到 Token 冲突，尝试找回任务[{}]可能已创建的实例...", taskId);
                }
                //todo 这里需要打印日志输出...
            }
            log.debug("任务[{}]执行异常，回滚删除锁，允许下次重试", taskId, e);
            try {
                lockRepo.deleteByLockId(taskId);
            } catch (Exception ex) {
                log.error("回滚失败", ex);
            }
            throw e;
        }
    }

    private Instance recoverInstance(ComputeClient computeClient, User user, LaunchInstanceDetails details) {
        try {
            ListInstancesRequest listRequest = ListInstancesRequest.builder()
                    .compartmentId(details.getCompartmentId())
                    .displayName(details.getDisplayName())
                    .build();
            ListInstancesResponse listResponse = computeClient.listInstances(listRequest);
            String targetName = details.getDisplayName();
            return listResponse.getItems().stream()
                    .filter(ins -> {
                        boolean nameMatch = targetName.equals(ins.getDisplayName());
                        boolean notTerminated = ins.getLifecycleState() != Instance.LifecycleState.Terminated;
                        return nameMatch && notTerminated;
                    })
                    .findFirst()
                    .orElse(null);
        } catch (Exception ex) {
            log.error("找回实例失败，taskId: {}", user.getBootId(), ex);
            return null;
        }
    }

    private String generateConfigToken(String taskId, LaunchInstanceDetails details) {
        StringBuilder tokenBuilder = new StringBuilder("instance-oci-start-");
        tokenBuilder.append(taskId);
        LaunchInstanceShapeConfigDetails shapeConfig = details.getShapeConfig();
        if (shapeConfig != null) {
            if (shapeConfig.getOcpus() != null) {
                tokenBuilder.append("-").append(shapeConfig.getOcpus());
            } else {
                tokenBuilder.append("-defCpu");
            }
            if (shapeConfig.getMemoryInGBs() != null) {
                tokenBuilder.append("-").append(shapeConfig.getMemoryInGBs());
            } else {
                tokenBuilder.append("-defMem");
            }
        }
        InstanceSourceDetails source = details.getSourceDetails();
        if (source instanceof InstanceSourceViaImageDetails) {
            InstanceSourceViaImageDetails imageDetails = (InstanceSourceViaImageDetails) source;
            Long diskSize = imageDetails.getBootVolumeSizeInGBs();

            if (diskSize != null) {
                tokenBuilder.append("-").append(diskSize);
            } else {
                tokenBuilder.append("-defDisk");
            }
        }
        return tokenBuilder.toString();
    }



    private static LaunchInstanceDetails createLaunchInstanceDetails(
            String compartmentId,
            AvailabilityDomain availabilityDomain,
            Shape shape,
            String imageId,
            Subnet subnet,
            NetworkSecurityGroup networkSecurityGroup,
            String script,
            User user) {
        String instanceName = "instance-" + user.getBootId();
        String encodedCloudInitScript = Base64.getEncoder().encodeToString(script.getBytes());
        Map<String, Object> extendedMetadata = new HashMap<>();
        /*extendedMetadata.put(
                "java-sdk-example-extended-metadata-key",
                "java-sdk-example-extended-metadata-value");
        extendedMetadata = Collections.unmodifiableMap(extendedMetadata);*/
        InstanceSourceViaImageDetails instanceSourceViaImageDetails =
                InstanceSourceViaImageDetails.builder()
                        .imageId(imageId)
                        .bootVolumeSizeInGBs(user.getDisk())
                        //.kmsKeyId((kmsKeyId == null || "".equals(kmsKeyId)) ? null : kmsKeyId)
                        .build();
        CreateVnicDetails createVnicDetails =
                CreateVnicDetails.builder()
                        .subnetId(subnet.getId())
                        .assignPublicIp(Boolean.TRUE)
                        .nsgIds(Collections.singletonList(networkSecurityGroup.getId()))
                        .build();
        LaunchInstanceAgentConfigDetails launchInstanceAgentConfigDetails =
                LaunchInstanceAgentConfigDetails.builder().isMonitoringDisabled(false).build();
        return LaunchInstanceDetails.builder()
                .availabilityDomain(availabilityDomain.getName())
                .compartmentId(compartmentId)
                .displayName(instanceName)
                // faultDomain is optional parameter
                //.faultDomain("FAULT-DOMAIN-2")
                .sourceDetails(instanceSourceViaImageDetails)
                .metadata(Collections.singletonMap("user_data", encodedCloudInitScript))
                //.extendedMetadata(extendedMetadata)
                .shape(shape.getShape())
                .createVnicDetails(createVnicDetails)
                // agentConfig is an optional parameter
                .agentConfig(launchInstanceAgentConfigDetails)
                //配置核心和内存
                .shapeConfig(LaunchInstanceShapeConfigDetails.
                        builder().
                        ocpus(user.getOcpus()).
                        memoryInGBs(user.getMemory()).
                        build())
                /*//配置磁盘大小
                .sourceDetails(InstanceSourceViaImageDetails.builder()
                        .imageId(imageId)
                        .bootVolumeSizeInGBs(user.getDisk())
                        .build())*/
                .build();
    }

    private void printInstance(User user,
            ComputeClient computeClient,
            VirtualNetworkClient virtualNetworkClient,
            Instance instance,
            OracleInstanceDetail oracleInstanceDetail,Shape.BillingType billingType,
                               SimpleAuthenticationDetailsProvider provider) {
        ListVnicAttachmentsRequest listVnicAttachmentsRequest =
                ListVnicAttachmentsRequest.builder().compartmentId(instance.getCompartmentId()).instanceId(instance.getId()).build();

        ListVnicAttachmentsResponse listVnicAttachmentsResponse =
                computeClient.listVnicAttachments(listVnicAttachmentsRequest);
        List<VnicAttachment> vnicAttachments = listVnicAttachmentsResponse.getItems();
        VnicAttachment vnicAttachment = vnicAttachments.get(0);

        GetVnicRequest getVnicRequest =
                GetVnicRequest.builder().vnicId(vnicAttachment.getVnicId()).build();
        GetVnicResponse getVnicResponse = virtualNetworkClient.getVnic(getVnicRequest);
        Vnic vnic = getVnicResponse.getVnic();
        String taskTag = "[TaskId=" + user.getBootId() + "] ";
        StringBuilder openSuccessLog = new StringBuilder();
        openSuccessLog.append(taskTag).append("<=======================================>\n")
                .append(taskTag).append("Instance create success detail: ").append(instance.getId()).append("\n")
                .append(taskTag).append("Public IP : ").append(vnic.getPublicIp()).append("\n")
                .append(taskTag).append("region : ").append(user.getRegion()).append("\n")
                .append(taskTag).append("Private IP : ").append(vnic.getPrivateIp()).append("\n")
                .append(taskTag).append("login root: root\n")
                .append(taskTag).append("login passWord: ").append(user.getRootPassword()).append("\n")
                .append(taskTag).append("<=======================================>");
        ociLogBuilder.buildOpenBootSuccess(openSuccessLog.toString());

        oracleInstanceDetail.setPublicIp(vnic.getPublicIp());
        oracleInstanceDetail.setPrivateIp(vnic.getPrivateIp());
        oracleInstanceDetail.setSuccess(true);
        oracleInstanceDetail.setRegion(user.getRegion());
        oracleInstanceDetail.setArchitecture(user.getArchitecture());
        oracleInstanceDetail.setUserName(user.getUserName());
        oracleInstanceDetail.setBillingType(billingType);
        oracleInstanceDetail.setRootPasswd(user.getRootPassword());
        oracleInstanceDetail.setInstance(instance);
        InstanceAgentConfig instanceAgentConfig = instance.getAgentConfig();

        eventPublisher.publishEvent(new OracleInstanceSuccessEvent(this, user, oracleInstanceDetail, provider));

    }

    public static BootVolume createBootVolume(
            BlockstorageClient blockstorageClient,
            String compartmentId,
            AvailabilityDomain availabilityDomain,
            Image image,
            String kmsKeyId)
            throws Exception {

        // find existing boot volume by image
        ListBootVolumesRequest listBootVolumesRequest =
                ListBootVolumesRequest.builder()
                        .availabilityDomain(availabilityDomain.getName())
                        .compartmentId(compartmentId)
                        .build();
        ListBootVolumesResponse listBootVolumesResponse =
                blockstorageClient.listBootVolumes(listBootVolumesRequest);
        List<BootVolume> bootVolumes = listBootVolumesResponse.getItems();
        String bootVolumeId = null;
        for (BootVolume bootVolume : bootVolumes) {
            if (BootVolume.LifecycleState.Available.equals(bootVolume.getLifecycleState())
                    && image.getId().equals(bootVolume.getImageId())) {
                bootVolumeId = bootVolume.getId();
                break;
            }
        }
        System.out.println("Found BootVolume: " + bootVolumeId);

        // create a new boot volume based on existing one
        BootVolumeSourceDetails bootVolumeSourceDetails =
                BootVolumeSourceFromBootVolumeDetails.builder().id(bootVolumeId).build();
        CreateBootVolumeDetails details =
                CreateBootVolumeDetails.builder()
                        .availabilityDomain(availabilityDomain.getName())
                        .compartmentId(compartmentId)
                        .displayName(bootVolumeName)
                        .sourceDetails(bootVolumeSourceDetails)
                        .kmsKeyId(kmsKeyId)
                        .build();
        CreateBootVolumeRequest createBootVolumeRequest =
                CreateBootVolumeRequest.builder().createBootVolumeDetails(details).build();
        CreateBootVolumeResponse createBootVolumeResponse =
                blockstorageClient.createBootVolume(createBootVolumeRequest);
        System.out.println(
                "Provisioning new BootVolume: " + createBootVolumeResponse.getBootVolume().getId());

        // wait for boot volume to be ready
        GetBootVolumeRequest getBootVolumeRequest =
                GetBootVolumeRequest.builder()
                        .bootVolumeId(createBootVolumeResponse.getBootVolume().getId())
                        .build();
        GetBootVolumeResponse getBootVolumeResponse =
                blockstorageClient
                        .getWaiters()
                        .forBootVolume(getBootVolumeRequest, BootVolume.LifecycleState.Available)
                        .execute();
        BootVolume bootVolume = getBootVolumeResponse.getBootVolume();

        System.out.println("Provisioned BootVolume: " + bootVolume.getId());
        System.out.println(bootVolume);
        System.out.println();

        return bootVolume;
    }


    public static String findRootCompartment(IdentityClient identityClient, String tenantId) {
        // 使用`compartmentIdInSubtree`参数来获取所有子区间
        ListCompartmentsRequest request = ListCompartmentsRequest.builder()
                .compartmentId(tenantId)
                .compartmentIdInSubtree(true)
                .accessLevel(ListCompartmentsRequest.AccessLevel.Accessible)
                .build();

        ListCompartmentsResponse response = identityClient.listCompartments(request);
        List<Compartment> compartments = response.getItems();

        // 根区间是没有parentCompartmentId的区间
        for (Compartment compartment : compartments) {
            if (compartment.getCompartmentId().equals(tenantId) && compartment.getId().equals(compartment.getCompartmentId())) {
                return compartment.getId(); // 返回根区间ID
            }
        }

        // 如果没有找到根区间，返回租户ID作为默认值
        return tenantId;
    }

    public static AvailabilityDomain getFirstAvailabilityDomain(
            final IdentityClient identityClient, final String compartmentId) {

        final ListAvailabilityDomainsResponse listAvailabilityDomainsResponse =
                identityClient.listAvailabilityDomains(
                        ListAvailabilityDomainsRequest.builder()
                                .compartmentId(compartmentId)
                                .build());

        final List<AvailabilityDomain> availabilityDomains =
                listAvailabilityDomainsResponse.getItems();
        return availabilityDomains.get(0);
    }


    public static OciGatewayVcnPair findMatchingInternetGateway(
            Collection<InternetGateway> items,
            Collection<Vcn> vcns) {
        Map<String, Vcn> vcnMap = vcns.stream()
                .collect(Collectors.toMap(
                        Vcn::getId,
                        Function.identity()
                ));
        for (InternetGateway item : items) {
            String igwVcnId = item.getVcnId();
            if (vcnMap.containsKey(igwVcnId)) {
                Vcn matchingVcn = vcnMap.get(igwVcnId);
                return new OciGatewayVcnPair(item, matchingVcn);
            }
        }
        return null;
    }


}
