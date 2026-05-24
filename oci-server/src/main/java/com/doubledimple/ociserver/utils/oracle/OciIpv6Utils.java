package com.doubledimple.ociserver.utils.oracle;

import com.oracle.bmc.core.*;
import com.oracle.bmc.core.model.*;
import com.oracle.bmc.core.requests.*;
import lombok.extern.slf4j.Slf4j;
import org.springframework.util.CollectionUtils;
import org.springframework.util.StringUtils;

import java.util.ArrayList;
import java.util.List;

/**
 * Utility class for Oracle Cloud Infrastructure IPv6 operations
 */
@Slf4j
public class OciIpv6Utils {

    /**
     * Creates a new IPv6 address for a VNIC
     *
     * @param virtualNetworkClient The VirtualNetworkClient
     * @param vnicId The ID of the VNIC
     * @return The created IPv6 address
     */
    public static Ipv6 createIpv6(VirtualNetworkClient virtualNetworkClient, String vnicId) {
        log.debug("Creating new IPv6 address for VNIC: {}", vnicId);

        CreateIpv6Details createIpv6Details = CreateIpv6Details.builder()
                .vnicId(vnicId)
                .build();

        CreateIpv6Request createIpv6Request = CreateIpv6Request.builder()
                .createIpv6Details(createIpv6Details)
                .build();

        Ipv6 ipv6 = virtualNetworkClient.createIpv6(createIpv6Request).getIpv6();
        waitForIpv6Available(virtualNetworkClient, ipv6.getId());

        log.debug("Created IPv6 address: {}", ipv6.getIpAddress());
        return ipv6;
    }

    /**
     * Deletes an IPv6 address
     *
     * @param virtualNetworkClient The VirtualNetworkClient
     * @param ipv6Id The ID of the IPv6 address
     */
    public static void deleteIpv6(VirtualNetworkClient virtualNetworkClient, String ipv6Id) {
        log.debug("Deleting IPv6 address with ID: {}", ipv6Id);

        DeleteIpv6Request deleteRequest = DeleteIpv6Request.builder()
                .ipv6Id(ipv6Id)
                .build();

        virtualNetworkClient.deleteIpv6(deleteRequest);
        waitForIpv6Deleted(virtualNetworkClient, ipv6Id);

        log.debug("IPv6 address deleted successfully");
    }

    /**
     * Ensures that the VCN has IPv6 enabled
     */
    public static Vcn ensureVcnWithIpv6(VirtualNetworkClient virtualNetworkClient, Vcn vcn) {
        log.debug("Ensuring VCN with IPv6: {}", vcn.getId());

        if (vcn.getIpv6CidrBlocks() == null || vcn.getIpv6CidrBlocks().isEmpty()) {
            log.debug("No IPv6 CIDR blocks found for VCN. Adding IPv6 CIDR...");
            AddVcnIpv6CidrDetails addVcnIpv6CidrDetails = AddVcnIpv6CidrDetails.builder().build();
            AddIpv6VcnCidrRequest addVcnIpv6CidrRequest = AddIpv6VcnCidrRequest.builder()
                    .vcnId(vcn.getId())
                    .addVcnIpv6CidrDetails(addVcnIpv6CidrDetails)
                    .build();

            virtualNetworkClient.addIpv6VcnCidr(addVcnIpv6CidrRequest);

            GetVcnRequest getVcnRequest = GetVcnRequest.builder().vcnId(vcn.getId()).build();
            vcn = virtualNetworkClient.getVcn(getVcnRequest).getVcn();
        }

        log.debug("VCN IPv6 CIDR blocks: {}", vcn.getIpv6CidrBlocks());
        return vcn;
    }

    /**
     * Ensures subnet has IPv6 CIDR block
     */
    public static Subnet ensureSubnetWithIpv6(VirtualNetworkClient virtualNetworkClient,
                                              Subnet subnet,
                                              Vcn vcn) {
        log.debug("Ensuring subnet with IPv6: {}", subnet.getId());

        if (StringUtils.isEmpty(subnet.getIpv6CidrBlock())) {
            log.debug("No IPv6 CIDR block found for subnet. Adding IPv6 CIDR...");

            List<String> ipv6CidrBlocks = vcn.getIpv6CidrBlocks();
            if (ipv6CidrBlocks == null || ipv6CidrBlocks.isEmpty()) {
                throw new RuntimeException("VCN does not have IPv6 CIDR blocks");
            }

            String subnetIpv6CidrBlock = ipv6CidrBlocks.get(0).replace("/56", "/64");

            AddSubnetIpv6CidrDetails addSubnetIpv6CidrDetails = AddSubnetIpv6CidrDetails.builder()
                    .ipv6CidrBlock(subnetIpv6CidrBlock)
                    .build();

            AddIpv6SubnetCidrRequest addSubnetIpv6CidrRequest = AddIpv6SubnetCidrRequest.builder()
                    .subnetId(subnet.getId())
                    .addSubnetIpv6CidrDetails(addSubnetIpv6CidrDetails)
                    .build();

            virtualNetworkClient.addIpv6SubnetCidr(addSubnetIpv6CidrRequest);

            GetSubnetRequest getSubnetRequest = GetSubnetRequest.builder().subnetId(subnet.getId()).build();
            subnet = virtualNetworkClient.getSubnet(getSubnetRequest).getSubnet();
        }

        log.debug("Subnet IPv6 CIDR block: {}", subnet.getIpv6CidrBlock());
        return subnet;
    }

    /**
     * Ensures IPv6 internet gateway exists and routes are configured
     */
    public static String ensureIpv6InternetGateway(VirtualNetworkClient virtualNetworkClient,
                                                   String compartmentId,
                                                   String vcnId) {
        log.debug("Ensuring IPv6 internet gateway for VCN: {}", vcnId);

        String gatewayId = findOrCreateIpv6Gateway(virtualNetworkClient, compartmentId, vcnId);
        ensureIpv6RouteRules(virtualNetworkClient, vcnId, gatewayId);

        return gatewayId;
    }

    /**
     * Enables or refreshes IPv6 for a VNIC
     */
    public static String enableOrRefreshVnicIpv6(VirtualNetworkClient virtualNetworkClient,
                                                 String vnicId,
                                                 boolean forceNewAddress) {
        log.debug("Enabling or refreshing IPv6 for VNIC: {}, force new: {}", vnicId, forceNewAddress);

        List<Ipv6> existingIpv6s = getIpv6Addresses(virtualNetworkClient, vnicId);
        boolean hasExistingIpv6 = !CollectionUtils.isEmpty(existingIpv6s);

        if (hasExistingIpv6 && !forceNewAddress) {
            String ipv6Address = existingIpv6s.get(0).getIpAddress();
            log.debug("Using existing IPv6 address: {}", ipv6Address);
            return ipv6Address;
        }

        if (hasExistingIpv6) {
            for (Ipv6 ipv6 : existingIpv6s) {
                log.debug("Deleting existing IPv6 address: {}", ipv6.getIpAddress());
                deleteIpv6(virtualNetworkClient, ipv6.getId());
            }
        }

        Ipv6 ipv6 = createIpv6(virtualNetworkClient, vnicId);
        String ipv6Address = ipv6.getIpAddress();
        log.debug("Enabled IPv6 with address: {}", ipv6Address);

        return ipv6Address;
    }

    // Private helper methods

    private static String findOrCreateIpv6Gateway(VirtualNetworkClient virtualNetworkClient,
                                                  String compartmentId,
                                                  String vcnId) {
        ListInternetGatewaysRequest listRequest = ListInternetGatewaysRequest.builder()
                .compartmentId(compartmentId)
                .vcnId(vcnId)
                .build();

        List<InternetGateway> gateways = virtualNetworkClient.listInternetGateways(listRequest)
                .getItems();

        for (InternetGateway gateway : gateways) {
            if (gateway.getLifecycleState() == InternetGateway.LifecycleState.Available) {
                log.debug("Found existing internet gateway: {}", gateway.getId());
                return gateway.getId();
            }
        }

        log.debug("Creating new internet gateway for VCN: {}", vcnId);

        CreateInternetGatewayDetails createDetails = CreateInternetGatewayDetails.builder()
                .compartmentId(compartmentId)
                .vcnId(vcnId)
                .displayName("IPv6-Internet-Gateway-" + System.currentTimeMillis())
                .build();

        CreateInternetGatewayRequest createRequest = CreateInternetGatewayRequest.builder()
                .createInternetGatewayDetails(createDetails)
                .build();

        InternetGateway gateway = virtualNetworkClient.createInternetGateway(createRequest)
                .getInternetGateway();

        log.debug("Created new IPv6 internet gateway: {}", gateway.getId());
        return gateway.getId();
    }

    private static void ensureIpv6RouteRules(VirtualNetworkClient virtualNetworkClient,
                                             String vcnId,
                                             String gatewayId) {
        log.debug("Ensuring IPv6 route rules for VCN: {}", vcnId);

        GetVcnRequest getVcnRequest = GetVcnRequest.builder().vcnId(vcnId).build();
        String defaultRouteTableId = virtualNetworkClient.getVcn(getVcnRequest)
                .getVcn().getDefaultRouteTableId();

        GetRouteTableRequest getRouteTableRequest = GetRouteTableRequest.builder()
                .rtId(defaultRouteTableId)
                .build();

        List<RouteRule> routeRules = virtualNetworkClient.getRouteTable(getRouteTableRequest)
                .getRouteTable()
                .getRouteRules();

        boolean hasIpv6Rule = false;
        for (RouteRule rule : routeRules) {
            if ("::/0".equals(rule.getDestination())) {
                hasIpv6Rule = true;
                log.debug("IPv6 route rule already exists");
                break;
            }
        }

        if (!hasIpv6Rule) {
            log.debug("Adding IPv6 route rule to route table: {}", defaultRouteTableId);

            List<RouteRule> updatedRules = new ArrayList<>(routeRules);

            RouteRule ipv6Rule = RouteRule.builder()
                    .destination("::/0")
                    .destinationType(RouteRule.DestinationType.CidrBlock)
                    .networkEntityId(gatewayId)
                    .build();

            updatedRules.add(ipv6Rule);

            UpdateRouteTableDetails updateDetails = UpdateRouteTableDetails.builder()
                    .routeRules(updatedRules)
                    .build();

            UpdateRouteTableRequest updateRequest = UpdateRouteTableRequest.builder()
                    .rtId(defaultRouteTableId)
                    .updateRouteTableDetails(updateDetails)
                    .build();

            virtualNetworkClient.updateRouteTable(updateRequest);
            log.debug("Successfully added IPv6 route rule");
        }
    }

    private static void waitForIpv6Available(VirtualNetworkClient virtualNetworkClient, String ipv6Id) {
        Ipv6.LifecycleState state = null;
        int maxRetries = 12;
        int retryCount = 0;

        while (state != Ipv6.LifecycleState.Available && retryCount < maxRetries) {
            try {
                Thread.sleep(2000);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new RuntimeException("Thread was interrupted", e);
            }

            GetIpv6Request getRequest = GetIpv6Request.builder().ipv6Id(ipv6Id).build();
            state = virtualNetworkClient.getIpv6(getRequest).getIpv6().getLifecycleState();
            retryCount++;

            log.debug("IPv6 state: {}, retry: {}/{}", state, retryCount, maxRetries);
        }

        if (state != Ipv6.LifecycleState.Available) {
            throw new RuntimeException("IPv6 address did not reach Available state after " + maxRetries + " retries");
        }
    }

    private static void waitForIpv6Deleted(VirtualNetworkClient virtualNetworkClient, String ipv6Id) {
        int maxRetries = 12;
        int retryCount = 0;
        boolean deleted = false;

        while (!deleted && retryCount < maxRetries) {
            try {
                Thread.sleep(2000);
                GetIpv6Request getRequest = GetIpv6Request.builder().ipv6Id(ipv6Id).build();
                virtualNetworkClient.getIpv6(getRequest);
                retryCount++;

                log.debug("IPv6 not yet deleted, retry: {}/{}", retryCount, maxRetries);
            } catch (Exception e) {
                deleted = true;
                log.debug("IPv6 deleted successfully");
            }
        }

        if (!deleted) {
            log.warn("IPv6 address may not have been fully deleted: {}", ipv6Id);
        }
    }

    /**
     * Gets the list of IPv6 addresses for a VNIC
     *
     * @param virtualNetworkClient The VirtualNetworkClient
     * @param vnicId The VNIC ID
     * @return List of Ipv6 objects
     */
    public static List<Ipv6> getIpv6Addresses(VirtualNetworkClient virtualNetworkClient, String vnicId) {
        // 构造请求来获取指定VNIC的所有IPv6地址
        ListIpv6sRequest listRequest = ListIpv6sRequest.builder()
                .vnicId(vnicId)
                .build();

        // 获取VNIC的所有IPv6地址
        List<Ipv6> ipv6s = virtualNetworkClient.listIpv6s(listRequest).getItems();

        // 返回获取到的IPv6地址列表
        return ipv6s;
    }

    /**
     * Gets the VNIC associated with an instance
     *
     * @param computeClient The ComputeClient
     * @param virtualNetworkClient The VirtualNetworkClient
     * @param instanceId The instance ID
     * @param compartmentId The compartment ID
     * @return The primary VNIC for the instance
     */
    public static Vnic getVnic(ComputeClient computeClient,
                               VirtualNetworkClient virtualNetworkClient,
                               String instanceId,
                               String compartmentId) {
        log.debug("Getting VNIC for instance: {}", instanceId);

        // List VNICs attached to the instance
        ListVnicAttachmentsRequest listAttachmentsRequest = ListVnicAttachmentsRequest.builder()
                .compartmentId(compartmentId)
                .instanceId(instanceId)
                .build();

        List<VnicAttachment> attachments = computeClient.listVnicAttachments(listAttachmentsRequest)
                .getItems();

        if (attachments.isEmpty()) {
            throw new RuntimeException("No VNIC attachments found for instance: " + instanceId);
        }

        // Get primary VNIC
        VnicAttachment primaryAttachment = attachments.stream()
                .filter(attachment -> attachment.getLifecycleState() == VnicAttachment.LifecycleState.Attached)
                .findFirst()
                .orElseThrow(() -> new RuntimeException("No attached VNIC found for instance: " + instanceId));

        // Get VNIC details
        GetVnicRequest getVnicRequest = GetVnicRequest.builder()
                .vnicId(primaryAttachment.getVnicId())
                .build();

        Vnic vnic = virtualNetworkClient.getVnic(getVnicRequest).getVnic();
        log.debug("Found VNIC with ID: {}", vnic.getId());

        return vnic;
    }

    /**
     * Gets a subnet by its OCID
     */
    public static Subnet getSubnetById(VirtualNetworkClient virtualNetworkClient, String subnetId) {
        GetSubnetRequest request = GetSubnetRequest.builder().subnetId(subnetId).build();
        return virtualNetworkClient.getSubnet(request).getSubnet();
    }

    /**
     * Gets a VCN by its OCID
     */
    public static Vcn getVcnById(VirtualNetworkClient virtualNetworkClient, String vcnId) {
        GetVcnRequest request = GetVcnRequest.builder().vcnId(vcnId).build();
        return virtualNetworkClient.getVcn(request).getVcn();
    }

}
