package com.doubledimple.ociserver.utils.oracle;

import com.alibaba.fastjson2.JSON;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ociserver.config.constant.SystemScriptShell;
import com.doubledimple.ociserver.config.exception.OciExceptionFactory;
import com.doubledimple.ociserver.pojo.domain.dto.User;
import com.doubledimple.ociserver.pojo.dto.OciComputerDto;
import com.doubledimple.ociserver.pojo.dto.OciGatewayVcnPair;
import com.doubledimple.ociserver.pojo.enums.ArchitectureEnum;
import com.doubledimple.ociserver.pojo.enums.OperationSystemEnum;
import com.doubledimple.ociserver.pojo.request.OciComputerCreateRequest;
import com.oracle.bmc.ClientConfiguration;
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.core.BlockstorageClient;
import com.oracle.bmc.core.ComputeClient;
import com.oracle.bmc.core.VirtualNetworkClient;
import com.oracle.bmc.core.model.CreateVnicDetails;
import com.oracle.bmc.core.model.Image;
import com.oracle.bmc.core.model.InstanceSourceViaImageDetails;
import com.oracle.bmc.core.model.InternetGateway;
import com.oracle.bmc.core.model.LaunchInstanceAgentConfigDetails;
import com.oracle.bmc.core.model.LaunchInstanceDetails;
import com.oracle.bmc.core.model.LaunchInstanceShapeConfigDetails;
import com.oracle.bmc.core.model.NetworkSecurityGroup;
import com.oracle.bmc.core.model.Shape;
import com.oracle.bmc.core.model.Subnet;
import com.oracle.bmc.core.model.Vcn;
import com.oracle.bmc.core.requests.ListImagesRequest;
import com.oracle.bmc.core.requests.ListShapesRequest;
import com.oracle.bmc.core.responses.ListImagesResponse;
import com.oracle.bmc.core.responses.ListShapesResponse;
import com.oracle.bmc.http.client.jersey.JerseyHttpProvider;
import com.oracle.bmc.identity.IdentityClient;
import com.oracle.bmc.identity.model.AvailabilityDomain;
import com.oracle.bmc.logging.LoggingManagementClient;
import com.oracle.bmc.workrequests.WorkRequestClient;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;

import java.util.ArrayList;
import java.util.Base64;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import static com.doubledimple.ociserver.config.exception.ErrorCode.NOT_AUTH;
import static com.doubledimple.ociserver.service.oracle.OracleCloudService.addInternetGatewayToDefaultRouteTable;
import static com.doubledimple.ociserver.service.oracle.OracleCloudService.createInternetGateway;
import static com.doubledimple.ociserver.service.oracle.OracleCloudService.createSubnet;
import static com.doubledimple.ociserver.service.oracle.OracleCloudService.findRootCompartment;
import static com.doubledimple.ociserver.service.oracle.OracleCloudService.getAvailabilityDomains;
import static com.doubledimple.ociserver.utils.oracle.OciCliUtils.addNetworkSecurityGroupSecurityRules;
import static com.doubledimple.ociserver.utils.oracle.OciCliUtils.createNetworkSecurityGroup;
import static com.doubledimple.ociserver.utils.oracle.OciCliUtils.createVcn;
import static com.doubledimple.ociserver.utils.oracle.OciUtils.checkShapes;
import com.doubledimple.ociserver.config.ProxyContext;

/**
 * @version 1.0.0
 * @ClassName OciComputerUtils
 * @Description 实例工具类
 * @Author doubleDimple
 * @Date 2025-10-29 13:36
 */
@Slf4j
public class OciComputerUtils {

    /**
    * @Description:  ociComputerDto(库里返回的数据)
    * @Param: [com.doubledimple.ociserver.pojo.dto.OciComputerDto, com.doubledimple.ociserver.pojo.domain.dto.User]
    * @return: void
    * @Author: 抢占实例
    * @Date: 10/29/25 2:53 PM
    */
    public static List<LaunchInstanceDetails> createDbInstanceDetails(OciComputerDto ociComputerDto,User user){
        List<LaunchInstanceDetails> launchInstanceDetailsList = new ArrayList<>();
        String cloudInitScript = SystemScriptShell.getShell(user.getRootPassword());
        String bootIdStr = ociComputerDto.getBootIdStr();
        String compartmentIdRoot = ociComputerDto.getCompartmentIdRoot();
        List<OciComputerDto.AvailabilityDomainName> availabilityDomainNameList = ociComputerDto.getAvailabilityDomainNameList();
        for (OciComputerDto.AvailabilityDomainName domainName : availabilityDomainNameList) {
             String availabilityDomainName = domainName.getAvailabilityDomainName();
             List<OciComputerDto.OciShape> ociShapeList = domainName.getOciShapeList();
            for (OciComputerDto.OciShape ociShape : ociShapeList) {
                OciComputerCreateRequest ociComputerCreateRequest = new OciComputerCreateRequest();
                ociComputerCreateRequest.setCompartmentId(compartmentIdRoot);
                ociComputerCreateRequest.setScript(cloudInitScript);
                ociComputerCreateRequest.setAvailabilityDomainName(availabilityDomainName);
                ociComputerCreateRequest.setShapeName(ociShape.getShapeName());
                ociComputerCreateRequest.setImageId(ociShape.getImageId());
                ociComputerCreateRequest.setSubnetId(ociShape.getSubnetId());
                ociComputerCreateRequest.setNetworkSecurityGroupId(ociShape.getNetworkSecurityGroupId());
                ociComputerCreateRequest.setUser(user);
                LaunchInstanceDetails launchInstanceDetails = createLaunchInstanceDetails(ociComputerCreateRequest);
                launchInstanceDetailsList.add(launchInstanceDetails);
            }
        }
        return launchInstanceDetailsList;
    }

    /**
    * @Description: buildSimpleAllNetWork
     * 构建一个网络信息组(不做镜像的事情)
    * @Param: [com.doubledimple.dao.entity.Tenant]
    * @return: com.doubledimple.ociserver.pojo.dto.OciComputerDto.AvailabilityDomainName
    * @Author: doubleDimple
    * @Date: 12/31/25 3:26 PM
    */
    public static List<OciComputerDto.AvailabilityDomainName> buildSimpleAllNetWork(Tenant tenant){
        SimpleAuthenticationDetailsProvider authenticationDetailsProvider = OciUtils.getProvider(tenant);
        String compartmentId = authenticationDetailsProvider.getTenantId();
        List<OciComputerDto.AvailabilityDomainName> availabilityDomainNames = new ArrayList<>();
        try(IdentityClient identityClient = IdentityClient.builder().clientConfigurator(ProxyContext.get()).build(authenticationDetailsProvider);
            VirtualNetworkClient virtualNetworkClient = VirtualNetworkClient.builder().clientConfigurator(ProxyContext.get()).configuration(ClientConfiguration.builder().build()).build(authenticationDetailsProvider)
            ) {
            String compartmentIdRoot = findRootCompartment(identityClient, compartmentId);
            List<AvailabilityDomain> availabilityDomains = getAvailabilityDomains(identityClient, compartmentIdRoot);
            for (AvailabilityDomain availabilityDomain : availabilityDomains) {
                OciComputerDto.AvailabilityDomainName domainName = new OciComputerDto.AvailabilityDomainName();
                List<OciComputerDto.OciShape> ociShapeList = new ArrayList<>();
                OciComputerDto.OciShape ociShape = new OciComputerDto.OciShape();
                OciGatewayVcnPair internetGatewayPair = createInternetGateway(virtualNetworkClient, compartmentId, createVcn(virtualNetworkClient, compartmentId));
                InternetGateway internetGateway = internetGatewayPair.getInternetGateway();
                Vcn vcn = internetGatewayPair.getVcn();
                addInternetGatewayToDefaultRouteTable(virtualNetworkClient,vcn,internetGateway);
                String networkCidrBlock = vcn.getCidrBlock();
                Subnet subnet = createSubnet(virtualNetworkClient, compartmentId, availabilityDomain, networkCidrBlock, vcn);
                if (null != subnet) {
                    NetworkSecurityGroup networkSecurityGroup = createNetworkSecurityGroup(virtualNetworkClient, compartmentId, vcn);
                    addNetworkSecurityGroupSecurityRules(virtualNetworkClient, networkSecurityGroup, networkCidrBlock);
                    ociShape.setCompartmentId(compartmentId);
                    ociShape.setNetworkSecurityGroupId(networkSecurityGroup.getId());
                    ociShape.setSubnetId(subnet.getId());
                    ociShape.setAvailabilityDomainName(availabilityDomain.getName());
                    ociShapeList.add(ociShape);
                    domainName.setAvailabilityDomainName(availabilityDomain.getName());
                    domainName.setOciShapeList(ociShapeList);
                    availabilityDomainNames.add(domainName);
                }
            }
            return availabilityDomainNames;
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }


    //构建启动实例参数(存库)
    public static OciComputerDto buildComputerParam(Tenant tenant,User user){
        OciComputerDto ociComputerDto = new OciComputerDto();
        List<OciComputerDto.AvailabilityDomainName> availabilityDomainNameList = new ArrayList<>();
        SimpleAuthenticationDetailsProvider authenticationDetailsProvider = OciUtils.getProvider(tenant);
        String compartmentId = authenticationDetailsProvider.getTenantId();
        try(IdentityClient identityClient = IdentityClient.builder().clientConfigurator(ProxyContext.get()).build(authenticationDetailsProvider);
            ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(authenticationDetailsProvider);
            WorkRequestClient workRequestClient = WorkRequestClient.builder().clientConfigurator(ProxyContext.get()).build(authenticationDetailsProvider);
            VirtualNetworkClient virtualNetworkClient = VirtualNetworkClient.builder().clientConfigurator(ProxyContext.get()).configuration(ClientConfiguration.builder().build()).build(authenticationDetailsProvider);
            BlockstorageClient blockstorageClient = BlockstorageClient.builder().clientConfigurator(ProxyContext.get()).build(authenticationDetailsProvider)) {

            identityClient.setRegion(user.getRegion());
            computeClient.setRegion(user.getRegion());
            workRequestClient.setRegion(user.getRegion());
            virtualNetworkClient.setRegion(user.getRegion());
            blockstorageClient.setRegion(user.getRegion());

            String compartmentIdRoot = findRootCompartment(identityClient, compartmentId);
            ociComputerDto.setCompartmentIdRoot(compartmentIdRoot);
            List<AvailabilityDomain> availabilityDomains = getAvailabilityDomains(identityClient, compartmentIdRoot);
            //获取有配额的可用性区域
            /*String architecture = user.getArchitecture();
            Integer freeResource = ArchitectureEnum.freeArmOrAmd(architecture);
            List<AvailabilityDomain> availabilityDomains = OciLimitsUtils.getSafeFreeAds(tenant, freeResource);*/
            if (!checkShapes(computeClient,authenticationDetailsProvider,availabilityDomains)){
                log.warn("当前租户:{}所有可用性域都不存在shapes,请检查账号是否已经风控", authenticationDetailsProvider.getTenantId());
                OciExceptionFactory.createException(NOT_AUTH);
            }
            for (AvailabilityDomain availabilityDomain : availabilityDomains) {
                OciComputerDto.AvailabilityDomainName domainName = new OciComputerDto.AvailabilityDomainName();
                List<Shape> shapes = getShape(computeClient, compartmentId, availabilityDomain, user.getArchitecture());
                if (shapes.size() > 0){
                    List<OciComputerDto.OciShape> ociShapeList = new ArrayList<>();
                    for (Shape shape : shapes) {
                        OciComputerDto.OciShape ociShape = new OciComputerDto.OciShape();
                        ociShape.setShapeName(shape.getShape());
                        Shape.BillingType billingType = shape.getBillingType();
                        ociComputerDto.setBillingType(billingType);
                        Image image = getImage(computeClient, compartmentId, shape, user);
                        List<Vcn> vcns = createVcn(virtualNetworkClient, compartmentId);
                        OciGatewayVcnPair internetGatewayPair = createInternetGateway(virtualNetworkClient, compartmentId, vcns);
                        InternetGateway internetGateway = internetGatewayPair.getInternetGateway();
                        Vcn vcn = internetGatewayPair.getVcn();
                        addInternetGatewayToDefaultRouteTable(virtualNetworkClient,vcn,internetGateway);
                        String networkCidrBlock = vcn.getCidrBlock();
                        Subnet subnet = createSubnet(virtualNetworkClient, compartmentId, availabilityDomain, networkCidrBlock, vcn);
                        if (null == subnet) {
                            continue;
                        }
                        NetworkSecurityGroup networkSecurityGroup = createNetworkSecurityGroup(virtualNetworkClient, compartmentId, vcn);
                        addNetworkSecurityGroupSecurityRules(virtualNetworkClient, networkSecurityGroup, networkCidrBlock);
                        ociShape.setCompartmentId(compartmentId);
                        ociShape.setImageId(image.getId());
                        ociShape.setNetworkSecurityGroupId(networkSecurityGroup.getId());
                        ociShape.setSubnetId(subnet.getId());
                        ociShape.setBillingType(shape.getBillingType());
                        ociShape.setAvailabilityDomainName(availabilityDomain.getName());
                        ociShapeList.add(ociShape);
                    }
                    domainName.setAvailabilityDomainName(availabilityDomain.getName());
                    domainName.setOciShapeList(ociShapeList);
                    availabilityDomainNameList.add(domainName);
                }
            }
            ociComputerDto.setAvailabilityDomainNameList(availabilityDomainNameList);
            return ociComputerDto;
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    /**
    * @Description: createLaunchInstanceDetails
    * @Param: [java.lang.String, java.lang.String, java.lang.String, java.lang.String, java.lang.String, java.lang.String, java.lang.String, com.doubledimple.ociserver.pojo.domain.dto.User]
    * @return: com.oracle.bmc.core.model.LaunchInstanceDetails
    * @Author: doubleDimple
    * @Date: 10/29/25 1:38 PM
    */
    public static LaunchInstanceDetails createLaunchInstanceDetails(
            OciComputerCreateRequest ociComputerCreateRequest) {

        String availabilityDomainName = ociComputerCreateRequest.getAvailabilityDomainName();
        String compartmentId = ociComputerCreateRequest.getCompartmentId();
        String imageId = ociComputerCreateRequest.getImageId();
        String networkSecurityGroupId = ociComputerCreateRequest.getNetworkSecurityGroupId();
        String subnetId = ociComputerCreateRequest.getSubnetId();
        String shapeName = ociComputerCreateRequest.getShapeName();
        User user = ociComputerCreateRequest.getUser();
        String script = ociComputerCreateRequest.getScript();

        String instanceName = "instance-" + user.getBootId();
        String encodedCloudInitScript = Base64.getEncoder().encodeToString(script.getBytes());
        InstanceSourceViaImageDetails instanceSourceViaImageDetails =
                InstanceSourceViaImageDetails.builder()
                        .imageId(imageId)
                        .bootVolumeSizeInGBs(user.getDisk())
                        .build();
        CreateVnicDetails createVnicDetails =
                CreateVnicDetails.builder()
                        .subnetId(subnetId)
                        .nsgIds(Collections.singletonList(networkSecurityGroupId))
                        .assignPublicIp(Boolean.TRUE)
                        .build();
        LaunchInstanceAgentConfigDetails launchInstanceAgentConfigDetails =
                LaunchInstanceAgentConfigDetails.builder().isMonitoringDisabled(false).build();
        return LaunchInstanceDetails.builder()
                .availabilityDomain(availabilityDomainName)
                .compartmentId(compartmentId)
                .displayName(instanceName)
                //配置磁盘大小
                .sourceDetails(instanceSourceViaImageDetails)
                .metadata(Collections.singletonMap("user_data", encodedCloudInitScript))
                .shape(shapeName)
                .createVnicDetails(createVnicDetails)
                .agentConfig(launchInstanceAgentConfigDetails)
                //配置核心和内存
                .shapeConfig(LaunchInstanceShapeConfigDetails.
                        builder().
                        ocpus(user.getOcpus()).
                        memoryInGBs(user.getMemory()).
                        build())
                //配置磁盘大小
                /*.sourceDetails(InstanceSourceViaImageDetails.builder()
                        .imageId(imageId)
                        .bootVolumeSizeInGBs(user.getDisk())
                        .build())*/
                .build();
    }


    public static List<Shape> getShape(
            ComputeClient computeClient,
            String compartmentId,
            AvailabilityDomain availabilityDomain,
            String architecture) {
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
        ArchitectureEnum type = ArchitectureEnum.getType(architecture);
        if (type == null) {
            type = ArchitectureEnum.ARM;
        }
        for (Shape vmShape : vmShapes) {
            if (type.getShapeDetail().equals(vmShape.getShape())) {
                shapesNewList.add(vmShape);
            }
        }
        return shapesNewList;
    }

    public static Image getImage(ComputeClient computeClient, String compartmentId, Shape shape, User user)
            throws Exception {
        String operatingSystem = user.getOperatingSystem();
        String operatingSystemVersion = user.getOperatingSystemVersion();
        if (StringUtils.isBlank(operatingSystem) || StringUtils.isBlank(operatingSystemVersion)){
            OperationSystemEnum systemType = OperationSystemEnum.getDefaultSystemType();
            operatingSystem = systemType.getType();
            operatingSystemVersion = systemType.getVersion();
        }

        ListImagesRequest listImagesRequest =
                ListImagesRequest.builder()
                        .shape(shape.getShape())
                        .compartmentId(compartmentId)
                        .operatingSystem(operatingSystem)
                        .operatingSystemVersion(operatingSystemVersion)
                        .build();
        ListImagesResponse response = computeClient.listImages(listImagesRequest);
        List<Image> images = response.getItems();
        if (images.isEmpty()) {
            return null;
        }
        Image image = images.get(0);

        return image;
    }
}
