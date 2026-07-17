package com.doubledimple.ociserver.utils.oracle;

import com.doubledimple.dao.entity.Tenant;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.nosql.NosqlClient;
import com.oracle.bmc.nosql.model.CreateTableDetails;
import com.oracle.bmc.nosql.model.QueryDetails;
import com.oracle.bmc.nosql.model.TableLimits;
import com.oracle.bmc.nosql.model.UpdateRowDetails;
import com.oracle.bmc.nosql.requests.CreateTableRequest;
import com.oracle.bmc.nosql.requests.DeleteRowRequest;
import com.oracle.bmc.nosql.requests.DeleteTableRequest;
import com.oracle.bmc.nosql.requests.GetRowRequest;
import com.oracle.bmc.nosql.requests.QueryRequest;
import com.oracle.bmc.nosql.requests.UpdateRowRequest;
import com.oracle.bmc.nosql.responses.CreateTableResponse;
import com.oracle.bmc.nosql.responses.GetRowResponse;
import com.oracle.bmc.nosql.responses.QueryResponse;
import com.oracle.bmc.nosql.responses.UpdateRowResponse;
import lombok.extern.slf4j.Slf4j;

import java.util.List;
import java.util.Map;
import com.doubledimple.ociserver.config.ProxyContext;

/**
 * OCI NoSQL 数据库管理工具类
 * 依赖 NosqlClient
 *
 * @author doubleDimple
 * @date 2026:04:02
 */
@Slf4j
public class OciNoSqlUtils {

    /**
     * @Description: 创建 NoSQL 数据表 (默认使用 Always Free 的免费资源配置)
     * @Param: [tenant, compartmentId, tableName, ddlStatement]
     * @Example ddlStatement: "CREATE TABLE IF NOT EXISTS saas_subscriptions (id STRING, user_id STRING, plan JSON, PRIMARY KEY(id))"
     */
    public static void createTable(Tenant tenant, String tableName, String ddlStatement) {
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
        String compartmentId = provider.getTenantId();
        try (NosqlClient nosqlClient = NosqlClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {

            // 设定表的容量限制。这里设定为免费额度的标准：50 Read, 50 Write, 50GB
            TableLimits limits = TableLimits.builder()
                    .maxReadUnits(50)
                    .maxWriteUnits(50)
                    .maxStorageInGBs(50)
                    .build();

            CreateTableDetails createTableDetails = CreateTableDetails.builder()
                    .name(tableName)
                    .compartmentId(compartmentId)
                    .ddlStatement(ddlStatement)
                    .tableLimits(limits)
                    .build();

            CreateTableRequest request = CreateTableRequest.builder()
                    .createTableDetails(createTableDetails)
                    .build();

            CreateTableResponse response = nosqlClient.createTable(request);
            log.info("成功发起建表请求: {}", tableName);

        } catch (Exception e) {
            log.error("创建 NoSQL 表 {} 失败", tableName, e);
        }
    }

    /**
     * @Description: 插入或更新一行数据 (Upsert)
     * @Param: [tenant, tableName, rowData]
     */
    public static boolean putRow(Tenant tenant, String tableName, Map<String, Object> rowData) {
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);

        try (NosqlClient nosqlClient = NosqlClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {

            UpdateRowDetails updateDetails = UpdateRowDetails.builder()
                    .compartmentId(provider.getTenantId()) // 默认使用租户根 compartment
                    .value(rowData)
                    .build();

            UpdateRowRequest request = UpdateRowRequest.builder()
                    .tableNameOrId(tableName)
                    .updateRowDetails(updateDetails)
                    .build();

            UpdateRowResponse response = nosqlClient.updateRow(request);
            log.debug("成功插入/更新数据至表: {}, 消耗写单位: {}", tableName, response.getUpdateRowResult().getUsage().getWriteUnitsConsumed());
            return true;

        } catch (Exception e) {
            log.error("向表 {} 插入数据失败", tableName, e);
            return false;
        }
    }

    /**
     * @Description: 根据主键查询单行数据
     * @Param: [tenant, tableName, keyMap]
     * @Example keyMap: Map.of("id", "sub_1001")
     */
    public static Map<String, Object> getRow(Tenant tenant, String tableName, List<String> keyNames, List<String> keys) {
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);

        try (NosqlClient nosqlClient = NosqlClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {

            GetRowRequest request = GetRowRequest.builder()
                    .tableNameOrId(tableName)
                    .compartmentId(provider.getTenantId())
                    .key(keys)
                    .build();

            GetRowResponse response = nosqlClient.getRow(request);
            if (response.getRow() != null) {
                return response.getRow().getValue();
            }

        } catch (Exception e) {
            log.error("从表 {} 获取数据失败", tableName, e);
        }
        return null;
    }

    /**
     * @Description: 执行 SQL 语句进行复杂查询
     * @Param: [tenant, compartmentId, statement]
     * @Example statement: "SELECT * FROM saas_subscriptions WHERE user_id = 'u_888'"
     */
    public static List<Map<String, Object>> queryData(Tenant tenant, String compartmentId, String statement) {
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);

        try (NosqlClient nosqlClient = NosqlClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {

            QueryDetails queryDetails = QueryDetails.builder()
                    .compartmentId(compartmentId)
                    .statement(statement)
                    .build();

            QueryRequest request = QueryRequest.builder()
                    .queryDetails(queryDetails)
                    .build();

            QueryResponse response = nosqlClient.query(request);
            List<Map<String, Object>> results = response.getQueryResultCollection().getItems();

            log.info("查询执行成功，共返回 {} 条结果", results.size());
            return results;

        } catch (Exception e) {
            log.error("执行 NoSQL 查询失败: {}", statement, e);
        }
        return null;
    }

    /**
     * @Description: 根据主键删除数据
     * @Param: [tenant, tableName, keys]
     */
    public static boolean deleteRow(Tenant tenant, String tableName, List<String> keys) {
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);

        try (NosqlClient nosqlClient = NosqlClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {

            DeleteRowRequest request = DeleteRowRequest.builder()
                    .tableNameOrId(tableName)
                    .compartmentId(provider.getTenantId())
                    .key(keys)
                    .build();

            nosqlClient.deleteRow(request);
            log.debug("成功从表 {} 删除数据", tableName);
            return true;

        } catch (Exception e) {
            log.error("删除表 {} 的数据失败", tableName, e);
            return false;
        }
    }

    /**
     * @Description: 删除表 (危险操作)
     * @Param: [tenant, tableName]
     */
    public static void dropTable(Tenant tenant, String tableName) {
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);

        try (NosqlClient nosqlClient = NosqlClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {


            DeleteTableRequest request = DeleteTableRequest.builder()
                    .tableNameOrId(tableName)
                    .compartmentId(provider.getTenantId())
                    .build();

            nosqlClient.deleteTable(request);
            log.info("成功发起删除表请求: {}", tableName);

        } catch (Exception e) {
            log.error("删除 NoSQL 表 {} 失败", tableName, e);
        }
    }
}
