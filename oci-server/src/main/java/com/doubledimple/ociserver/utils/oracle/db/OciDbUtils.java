package com.doubledimple.ociserver.utils.oracle.db;

import com.doubledimple.dao.entity.DbConfig;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ociserver.config.exception.OciExceptionFactory;
import com.doubledimple.ociserver.pojo.dto.OciComputerDto;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.mysql.DbSystemClient;
import com.oracle.bmc.mysql.MysqlaasClient;
import com.oracle.bmc.mysql.model.CreateDbSystemDetails;
import com.oracle.bmc.mysql.model.DbSystem;
import com.oracle.bmc.mysql.model.DbSystemSummary;
import com.oracle.bmc.mysql.model.ShapeSummary;
import com.oracle.bmc.mysql.model.UpdateDbSystemDetails;
import com.oracle.bmc.mysql.requests.CreateDbSystemRequest;
import com.oracle.bmc.mysql.requests.DeleteDbSystemRequest;
import com.oracle.bmc.mysql.requests.GetDbSystemRequest;
import com.oracle.bmc.mysql.requests.ListDbSystemsRequest;
import com.oracle.bmc.mysql.requests.ListShapesRequest;
import com.oracle.bmc.mysql.requests.UpdateDbSystemRequest;
import com.oracle.bmc.mysql.responses.CreateDbSystemResponse;
import com.oracle.bmc.mysql.responses.ListDbSystemsResponse;
import com.oracle.bmc.mysql.responses.ListShapesResponse;
import com.oracle.bmc.networkloadbalancer.NetworkLoadBalancerClient;
import com.oracle.bmc.networkloadbalancer.model.Backend;
import com.oracle.bmc.networkloadbalancer.model.BackendSetDetails;
import com.oracle.bmc.networkloadbalancer.model.CreateNetworkLoadBalancerDetails;
import com.oracle.bmc.networkloadbalancer.model.HealthCheckProtocols;
import com.oracle.bmc.networkloadbalancer.model.HealthChecker;
import com.oracle.bmc.networkloadbalancer.model.IpAddress;
import com.oracle.bmc.mysql.model.DbSystem.LifecycleState;
import com.oracle.bmc.networkloadbalancer.model.ListenerDetails;
import com.oracle.bmc.networkloadbalancer.model.ListenerProtocols;
import com.oracle.bmc.networkloadbalancer.model.NetworkLoadBalancer;
import com.oracle.bmc.networkloadbalancer.model.NetworkLoadBalancerSummary;
import com.oracle.bmc.networkloadbalancer.model.NetworkLoadBalancingPolicy;
import com.oracle.bmc.networkloadbalancer.requests.CreateNetworkLoadBalancerRequest;
import com.oracle.bmc.networkloadbalancer.requests.DeleteNetworkLoadBalancerRequest;
import com.oracle.bmc.networkloadbalancer.requests.GetNetworkLoadBalancerRequest;
import com.oracle.bmc.networkloadbalancer.requests.ListNetworkLoadBalancersRequest;
import com.oracle.bmc.networkloadbalancer.responses.ListNetworkLoadBalancersResponse;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;

import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static com.doubledimple.ociserver.utils.oracle.OciComputerUtils.buildSimpleAllNetWork;
import static com.doubledimple.ociserver.utils.oracle.OciUtils.getProvider;
import com.doubledimple.ociserver.config.ProxyContext;

/**
 * @version 1.0.0
 * @ClassName OciDbUtils
 * @Description see https://docs.oracle.com/en-us/iaas/api/#/en/mysql/20190415/DbSystem/CreateDbSystem
 * @Author doubleDimple
 * @Date 2025-12-30 09:12
 */
@Slf4j
public class OciDbUtils {

    public static final String DEFAULT_MYSQL_NLB_DISPLAY_NAME = "OCI_START_MYSQL_NLB";
    public static final String DEFAULT_MYSQL_NAME = "OCI_START_MYSQL_FREE";

    private static final String FREE_SHAPE_NAME = "MySQL.Free";

    private static final int FREE_MYSQL_STORAGE_GB = 50;

    private static final int MYSQL_PORT = 3306;

    private static final String DEFAULT_MYSQL_ADMIN = "admin";

    private static final String ORIGINAL_ADMIN = "original_admin";
    private static final String ORIGINAL_ADMIN_PASSWORD = "original_admin_password";

    private static final String LOWER = "abcdefghijklmnopqrstuvwxyz";
    private static final String UPPER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    private static final String DIGITS = "0123456789";
    private static final String SPECIAL = "#_$-!@";



    /**
    * @Description: resetMysqlPassword
     * 重置数据库密码
    * @Param: [com.doubledimple.dao.entity.Tenant, java.lang.String, java.lang.String]
    * @return: void
    * @Author: doubleDimple
    * @Date: 12/31/25 11:36 PM
    */
    public static boolean resetMysqlUserAndPass(Tenant tenant,String dbId,String adminUser,String adminPass){
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        Map<String, String> metaData = new HashMap<>();
        metaData.put(ORIGINAL_ADMIN,adminUser);
        metaData.put(ORIGINAL_ADMIN_PASSWORD,adminPass);
        try(DbSystemClient mysqlClient = DbSystemClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
            UpdateDbSystemRequest request = UpdateDbSystemRequest.builder()
                    .dbSystemId(dbId)
                    .updateDbSystemDetails(UpdateDbSystemDetails.builder()
                            .adminPassword(adminPass)
                            .freeformTags(metaData)
                            .build())
                    .build();
            mysqlClient.updateDbSystem(request);
            return true;
        }catch (Exception e){
            log.error("resetMysqlPassword error: {}", e.getMessage());
            throw new RuntimeException("reset mysql passWd fail: " + e.getMessage());
        }
    }


    /**
    * @Description: query tenant region mysql instance
    * @Param: [com.doubledimple.dao.entity.Tenant]
    * @return: java.util.List<com.doubledimple.dao.entity.DbConfig>
    * @Author: doubleDimple
    * @Date: 1/1/26 7:09 AM
    */
    public static List<DbConfig> queryMysqlInstance(Tenant tenant) {
        List<DbConfig> dbConfigList = new ArrayList<>();
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        String compartmentId = provider.getTenantId();

        try (DbSystemClient mysqlClient = DbSystemClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
            ListDbSystemsRequest listRequest =
                    com.oracle.bmc.mysql.requests.ListDbSystemsRequest.builder()
                            .compartmentId(compartmentId)
                            .build();

            ListDbSystemsResponse listResponse = mysqlClient.listDbSystems(listRequest);

            for (DbSystemSummary summary : listResponse.getItems()) {
                if (summary.getLifecycleState() != DbSystem.LifecycleState.Deleted &&
                        summary.getLifecycleState() != DbSystem.LifecycleState.Deleting) {
                    log.debug("fund MySQL instance: {}, get private IP...", summary.getId());
                    GetDbSystemRequest getRequest = GetDbSystemRequest.builder()
                            .dbSystemId(summary.getId())
                            .build();
                    DbSystem dbSystem = mysqlClient.getDbSystem(getRequest).getDbSystem();
                    if (dbSystem != null){
                        DbConfig dbConfig = createDbConfig(tenant, dbSystem, null,null, null);
                        dbConfigList.add(dbConfig);
                    }
                }
            }
            return dbConfigList;
        } catch (Exception e) {
            log.error("execute MySQL fail: {}", e.getMessage(), e);
            return null;
        }

    }
    /**
     * CREATE MySQL
     */
    public static DbConfig createFreeMysqlDbSystem(Tenant tenant, String displayName, String subnetId, String adminUser, String adminPass, String availabilityDomainName) {
        DbConfig dbConfig = new DbConfig();
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        String compartmentId = provider.getTenantId();

        try (DbSystemClient mysqlClient = DbSystemClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
            ListDbSystemsRequest listRequest = ListDbSystemsRequest.builder()
                    .compartmentId(compartmentId)
                    .displayName(displayName)
                    .build();

            ListDbSystemsResponse listResponse = mysqlClient.listDbSystems(listRequest);
            for (DbSystemSummary summary : listResponse.getItems()) {
                if (summary.getLifecycleState() != DbSystem.LifecycleState.Deleted &&
                        summary.getLifecycleState() != DbSystem.LifecycleState.Deleting) {

                    DbSystem dbSystem = mysqlClient.getDbSystem(GetDbSystemRequest.builder()
                            .dbSystemId(summary.getId()).build()).getDbSystem();
                    if (dbSystem != null) {
                        dbConfig.setDbId(dbSystem.getId());
                        dbConfig.setDbPrivateUrl(dbSystem.getIpAddress());
                        return dbConfig;
                    }
                }
            }
            Map<String, String> metaData = new HashMap<>();
            metaData.put(ORIGINAL_ADMIN, adminUser);
            metaData.put(ORIGINAL_ADMIN_PASSWORD, adminPass);
            CreateDbSystemDetails details = CreateDbSystemDetails.builder()
                    .compartmentId(compartmentId)
                    .displayName(displayName)
                    .shapeName(FREE_SHAPE_NAME)
                    .subnetId(subnetId)
                    .availabilityDomain(availabilityDomainName)
                    .adminUsername(adminUser)
                    .adminPassword(adminPass)
                    .dataStorageSizeInGBs(FREE_MYSQL_STORAGE_GB)
                    .freeformTags(metaData)
                    .build();

            log.debug("未找到实例，发送创建 MySQL Always Free 请求: {}", displayName);
            CreateDbSystemResponse response = mysqlClient.createDbSystem(CreateDbSystemRequest.builder()
                    .createDbSystemDetails(details).build());

            final DbSystem finalDbSystem = response.getDbSystem();
            return createDbConfig(tenant, finalDbSystem, adminUser, adminPass, null);
        } catch (Exception e) {
            OciExceptionFactory.buildException(e);
            return null;
        }
    }

    /**
     * 终止
     */
    public static boolean terminateMysqlDbSystem(Tenant tenant, String dbSystemId) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        boolean b = deleteNlbByDisplayName(tenant, provider);
        if (!b) {
            return false;
        }
        try (DbSystemClient mysqlClient = DbSystemClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
            DeleteDbSystemRequest request = DeleteDbSystemRequest.builder()
                    .dbSystemId(dbSystemId)
                    .build();

            log.debug("deleting MySQL instance: {}", dbSystemId);
            mysqlClient.deleteDbSystem(request);
            return true;
        } catch (Exception e) {
            log.error("delete MySQL fail: {}", e.getMessage());
            return false;
        }
    }

    /**
    * @Description: getMysqlShapes
    * @Param: [com.doubledimple.dao.entity.Tenant]
    * @return: java.util.List<com.oracle.bmc.mysql.model.ShapeSummary>
    * @Author: doubleDimple
    * @Date: 12/30/25 9:32 AM
    */
    public static List<ShapeSummary> getMysqlShapes(Tenant tenant) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        List<ShapeSummary> shapes = new ArrayList<>();

        try (MysqlaasClient client = MysqlaasClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
            ListShapesRequest.Builder builder = ListShapesRequest.builder();
            builder.compartmentId(provider.getTenantId());
            builder.isSupportedFor(Collections.singletonList(ListShapesRequest.IsSupportedFor.Dbsystem));
            ListShapesRequest listShapesRequest = builder
                    .build();

            ListShapesResponse response = client.listShapes(listShapesRequest);
            shapes = response.getItems();

            for (ShapeSummary shape : shapes) {
                log.info("fund Shape: {}, CPU: {}, MEM: {}GB",
                        shape.getName(), shape.getCpuCoreCount(), shape.getMemorySizeInGBs());
            }

        } catch (Exception e) {
            log.error("fund MySQL Shapes fail: {}", e.getMessage(), e);
        }
        return shapes;
    }

    public static DbConfig createMysql(Tenant tenant){
        return createMysql(tenant,generateCustomAdminUsername());
    }

    /**
    * @Description: createMysqlDbSystemAndNlb
     * 一键创建mysql并返回公网ip
    * @Param: [com.doubledimple.dao.entity.Tenant, java.lang.String, java.lang.String, java.lang.String]
    * @return: java.lang.String
    * @Author: renyx
    * @Date: 12/31/25 2:51 PM
    */
    public static DbConfig createMysql(Tenant tenant,String adminUser) {
        if (StringUtils.isBlank(adminUser)) adminUser = generateCustomAdminUsername();
        String adminPass = generateSecurePassword();
        List<OciComputerDto.AvailabilityDomainName> availabilityDomainNames = buildSimpleAllNetWork(tenant);
        for (OciComputerDto.AvailabilityDomainName domainName : availabilityDomainNames) {
            List<OciComputerDto.OciShape> ociShapeList = domainName.getOciShapeList();
            if (ociShapeList.size() == 0){
                log.warn("not fund oci network group and not not create MYSQL instance ");
                return null;
            }
            OciComputerDto.OciShape ociShape = ociShapeList.get(0);
            DbConfig freeMysqlDbSystem = createFreeMysqlDbSystem(tenant, DEFAULT_MYSQL_NAME, ociShape.getSubnetId(), adminUser, adminPass, ociShape.getAvailabilityDomainName());
            if (freeMysqlDbSystem != null){
                if (freeMysqlDbSystem.getDbStatus().equals(LifecycleState.Active.getValue())){
                    String dbPrivateUrl = freeMysqlDbSystem.getDbPrivateUrl();
                    String dbPublicIp = getDefaultMysqlNlbDisplayName(tenant, ociShape.getSubnetId(), dbPrivateUrl);
                    freeMysqlDbSystem.setDbPublicUrl(dbPublicIp);
                }
                return freeMysqlDbSystem;
            }
        }
        return null;
    }

    /**
    * @Description: bindPublicIpForMysql
    * @Param: [com.doubledimple.dao.entity.Tenant, com.doubledimple.dao.entity.DbConfig]
    * @return: void
    * @Author: doubleDimple
    * @Date: 1/1/26 8:03 PM
    */
    public static String bindPublicIpForMysql(Tenant tenant, DbConfig dbConfig) {
        String dbPrivateUrl = dbConfig.getDbPrivateUrl();
        return getDefaultMysqlNlbDisplayName(tenant, dbConfig.getSubnetId(), dbPrivateUrl);
    }

    /**
    * @Description: getDefaultMysqlNlbDisplayName
    * @Param: [com.doubledimple.dao.entity.Tenant, java.lang.String, java.lang.String]
    * @return: java.lang.String
    * @Author: doubleDimple
    * @Date: 12/31/25 2:46 PM
    */
    public static String getDefaultMysqlNlbDisplayName(Tenant tenant,String subnetId, String dbPrivateUrl) {
        return getOrCreateNlbPublicIp(tenant, DEFAULT_MYSQL_NLB_DISPLAY_NAME, subnetId, dbPrivateUrl);
    }



    /**
     * 为 MySQL 创建公网网络负载均衡器 (NLB)
     *
     * @param tenant       租户信息
     * @param displayName         NLB 名称
     * @param subnetId     公网子网 ID (必须是 Public Subnet)
     * @param dbPrivateUrl  MySQL 实例的私有 IP
     * @return NLB 的公网 IP 地址
     */
    public static String getOrCreateNlbPublicIp(Tenant tenant, String displayName, String subnetId, String dbPrivateUrl) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        String compartmentId = provider.getTenantId();

        try (NetworkLoadBalancerClient nlbClient = NetworkLoadBalancerClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {

            log.info("checking ths same name {} nlb...", displayName);
            ListNetworkLoadBalancersRequest listRequest = ListNetworkLoadBalancersRequest.builder()
                    .compartmentId(compartmentId)
                    .displayName(displayName)
                    .build();

            ListNetworkLoadBalancersResponse listResponse = nlbClient.listNetworkLoadBalancers(listRequest);
            List<NetworkLoadBalancerSummary> items = listResponse.getNetworkLoadBalancerCollection().getItems();

            for (NetworkLoadBalancerSummary summary : items) {
                if (displayName.equals(summary.getDisplayName()) &&
                        !summary.getLifecycleState().equals(LifecycleState.Deleted)) {

                    log.info("fund NLB: {}, get IP...", summary.getId());
                    GetNetworkLoadBalancerRequest getRequest = GetNetworkLoadBalancerRequest.builder()
                            .networkLoadBalancerId(summary.getId())
                            .build();
                    NetworkLoadBalancer existingNlb = nlbClient.getNetworkLoadBalancer(getRequest).getNetworkLoadBalancer();

                    return extractPublicIp(existingNlb);
                }
            }
            String backendSetName = "mysql-bs";
            BackendSetDetails backendSetDetails = BackendSetDetails.builder()
                    .policy(NetworkLoadBalancingPolicy.FiveTuple)
                    .backends(Collections.singletonList(Backend.builder()
                            .ipAddress(dbPrivateUrl)
                            .port(MYSQL_PORT)
                            .weight(1)
                            .name("mysql-backend")
                            .build()))
                    .healthChecker(HealthChecker.builder()
                            .protocol(HealthCheckProtocols.Tcp)
                            .port(MYSQL_PORT)
                            .build())
                    .build();

            Map<String, BackendSetDetails> bsMap = new HashMap<>();
            bsMap.put(backendSetName, backendSetDetails);

            Map<String, ListenerDetails> lsMap = new HashMap<>();
            lsMap.put("mysql-ls", ListenerDetails.builder()
                    .name("mysql-ls")
                    .port(MYSQL_PORT)
                    .protocol(ListenerProtocols.Tcp)
                    .defaultBackendSetName(backendSetName)
                    .build());

            CreateNetworkLoadBalancerDetails details = CreateNetworkLoadBalancerDetails.builder()
                    .compartmentId(compartmentId)
                    .displayName(displayName)
                    .subnetId(subnetId)
                    .isPrivate(false)
                    .backendSets(bsMap)
                    .listeners(lsMap)
                    .build();

            log.info("not fund NLB，creating NLB...");
            String newNlbId = nlbClient.createNetworkLoadBalancer(
                    CreateNetworkLoadBalancerRequest.builder().createNetworkLoadBalancerDetails(details).build()
            ).getNetworkLoadBalancer().getId();
            return waitForActiveAndGetIp(nlbClient, newNlbId);
        } catch (Exception e) {
            log.error("execute NLB fail: {}", e.getMessage(), e);
            return null;
        }
    }

    public static boolean deleteNlbByDisplayName(Tenant tenant,SimpleAuthenticationDetailsProvider provider) {
        if (provider == null){
            provider = getProvider(tenant);
        }
        String compartmentId = provider.getTenantId();
        try (NetworkLoadBalancerClient nlbClient = NetworkLoadBalancerClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {

            ListNetworkLoadBalancersRequest listRequest = ListNetworkLoadBalancersRequest.builder()
                    .compartmentId(compartmentId)
                    .displayName(DEFAULT_MYSQL_NLB_DISPLAY_NAME)
                    .build();

            ListNetworkLoadBalancersResponse listResponse = nlbClient.listNetworkLoadBalancers(listRequest);
            List<NetworkLoadBalancerSummary> items = listResponse.getNetworkLoadBalancerCollection().getItems();

            String targetNlbId = null;
            for (NetworkLoadBalancerSummary summary : items) {
                if (summary.getLifecycleState() != com.oracle.bmc.networkloadbalancer.model.LifecycleState.Deleted &&
                        summary.getLifecycleState() != com.oracle.bmc.networkloadbalancer.model.LifecycleState.Deleting) {
                    targetNlbId = summary.getId();
                    break;
                }
            }

            if (targetNlbId == null) {
                return true;
            }
            DeleteNetworkLoadBalancerRequest deleteRequest = DeleteNetworkLoadBalancerRequest.builder()
                    .networkLoadBalancerId(targetNlbId)
                    .build();

            nlbClient.deleteNetworkLoadBalancer(deleteRequest);
            return true;

        } catch (Exception e) {
            log.error("删除 NLB 失败: {}", e.getMessage(), e);
            return false;
        }
    }

    private static String extractPublicIp(NetworkLoadBalancer nlb) {
        for (IpAddress ip : nlb.getIpAddresses()) {
            if (ip.getIsPublic()) {
                return ip.getIpAddress();
            }
        }
        return null;
    }

    private static String waitForActiveAndGetIp(NetworkLoadBalancerClient client, String nlbId) throws InterruptedException {
        for (int i = 0; i < 30; i++) {
            NetworkLoadBalancer nlb = client.getNetworkLoadBalancer(
                    GetNetworkLoadBalancerRequest.builder().networkLoadBalancerId(nlbId).build()
            ).getNetworkLoadBalancer();

            if (nlb.getLifecycleState().equals(com.oracle.bmc.networkloadbalancer.model.LifecycleState.Active)) {
                return extractPublicIp(nlb);
            }
            log.debug("NLB status {}, waiting...", nlb.getLifecycleState());
            Thread.sleep(10000);
        }
        return null;
    }

    public static String generateSecurePassword() {
        SecureRandom random = new SecureRandom();
        List<Character> passwordChars = new ArrayList<>();
        passwordChars.add(LOWER.charAt(random.nextInt(LOWER.length())));
        passwordChars.add(UPPER.charAt(random.nextInt(UPPER.length())));
        passwordChars.add(DIGITS.charAt(random.nextInt(DIGITS.length())));
        passwordChars.add(SPECIAL.charAt(random.nextInt(SPECIAL.length())));
        String allChars = LOWER + UPPER + DIGITS + SPECIAL;
        for (int i = 0; i < 12; i++) {
            passwordChars.add(allChars.charAt(random.nextInt(allChars.length())));
        }
        Collections.shuffle(passwordChars);
        StringBuilder password = new StringBuilder();
        for (Character c : passwordChars) {
            password.append(c);
        }
        return password.toString();
    }

    public static String generateCustomAdminUsername() {
        String prefix = "oci_start_";
        String suffix = "_admin";
        SecureRandom random = new SecureRandom();
        StringBuilder sb = new StringBuilder();
        sb.append(prefix);
        for (int i = 0; i < 3; i++) {
            int index = random.nextInt(LOWER.length());
            sb.append(LOWER.charAt(index));
        }
        sb.append(suffix);
        return sb.toString();
    }

    /**
     * 根据 dbId (OCID) 获取云端 MySQL 实例详情
     */
    public static DbConfig getDbSystemDetail(Tenant tenant, DbConfig dbConfig) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        try (DbSystemClient mysqlClient = DbSystemClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
            GetDbSystemRequest request = GetDbSystemRequest.builder()
                    .dbSystemId(dbConfig.getDbId())
                    .build();
            DbSystem dbSystem = mysqlClient.getDbSystem(request).getDbSystem();
            return createDbConfig(tenant, dbSystem, dbConfig.getDbName(),dbConfig.getDbPassword() , dbConfig.getDbPublicUrl());
        } catch (Exception e) {
            log.error("获取 OCI 数据库详情失败, dbId: {}", dbConfig.getDbId(), e);
            return null;
        }
    }

    public static DbConfig createDbConfig(Tenant tenant, DbSystem dbSystem,String adminUser,String adminPassword,String dbPublicUrl) {
        if (adminUser == null) adminUser = "";
        if (adminPassword == null) adminPassword = "";
        if (dbPublicUrl == null) dbPublicUrl = "";
        DbConfig dbConfig = new DbConfig();
        dbConfig.setTenantId(tenant.getId());
        dbConfig.setDbName(adminUser);
        dbConfig.setDbPrivateUrl(dbSystem.getIpAddress());
        dbConfig.setDbPublicUrl(dbPublicUrl);
        dbConfig.setDbPort(dbSystem.getPort());
        dbConfig.setDbPassword(adminPassword);
        dbConfig.setDbId(dbSystem.getId());
        dbConfig.setDbVersion(dbSystem.getMysqlVersion());
        dbConfig.setDataStorageSizeInGBs(dbSystem.getDataStorageSizeInGBs());
        dbConfig.setDatabaseMode(dbSystem.getDatabaseMode().getValue());
        dbConfig.setDisplayName(dbSystem.getDisplayName());
        dbConfig.setHighlyAvailable(dbSystem.getIsHighlyAvailable() ? 1 : 0);
        dbConfig.setShapeName(dbSystem.getShapeName());
        dbConfig.setAvailabilityDomain(dbSystem.getAvailabilityDomain());
        dbConfig.setDbType(1);
        dbConfig.setCloudType(1);
        dbConfig.setSubnetId(dbSystem.getSubnetId());
        Map<String, String> freeformTags = dbSystem.getFreeformTags();
        DbSystem.LifecycleState lifecycleState = dbSystem.getLifecycleState();
        dbConfig.setDbStatus(lifecycleState.getValue());
        if (freeformTags.containsKey(ORIGINAL_ADMIN)){
            dbConfig.setDbName(freeformTags.get(ORIGINAL_ADMIN));
        }
        if (freeformTags.containsKey(ORIGINAL_ADMIN_PASSWORD)){
            dbConfig.setDbPassword(freeformTags.get(ORIGINAL_ADMIN_PASSWORD));
        }
        return dbConfig;
     }
}
