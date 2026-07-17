package com.doubledimple.ociserver.utils.oracle;

import cn.hutool.json.JSONUtil;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ociserver.pojo.domain.dto.OciClassLoaderPojo;
import com.doubledimple.ociserver.pojo.domain.dto.User;
import com.doubledimple.ociserver.pojo.enums.AccountTypeEnum;
import com.doubledimple.ociserver.pojo.enums.ArchitectureEnum;
import com.doubledimple.ociserver.pojo.request.TenancyDetail;
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.core.ComputeClient;
import com.oracle.bmc.core.VirtualNetworkClient;
import com.oracle.bmc.core.model.Shape;
import com.oracle.bmc.core.model.Vcn;
import com.oracle.bmc.core.requests.ListShapesRequest;
import com.oracle.bmc.core.requests.ListVcnsRequest;
import com.oracle.bmc.core.responses.ListShapesResponse;
import com.oracle.bmc.core.responses.ListVcnsResponse;
import com.oracle.bmc.identity.Identity;
import com.oracle.bmc.identity.IdentityClient;
import com.oracle.bmc.identity.model.RegionSubscription;
import com.oracle.bmc.identity.requests.GetCompartmentRequest;
import com.oracle.bmc.identity.requests.GetTenancyRequest;
import com.oracle.bmc.identity.responses.GetCompartmentResponse;
import com.oracle.bmc.identity.responses.GetTenancyResponse;
import com.oracle.bmc.logging.LoggingManagementClient;
import com.oracle.bmc.logging.model.Configuration;
import com.oracle.bmc.logging.model.CreateLogDetails;
import com.oracle.bmc.logging.model.CreateLogGroupDetails;
import com.oracle.bmc.logging.model.LogGroupSummary;
import com.oracle.bmc.logging.model.OciService;
import com.oracle.bmc.logging.requests.CreateLogGroupRequest;
import com.oracle.bmc.logging.requests.CreateLogRequest;
import com.oracle.bmc.logging.requests.ListLogGroupsRequest;
import com.oracle.bmc.logging.requests.ListLogsRequest;
import com.oracle.bmc.logging.responses.CreateLogGroupResponse;
import com.oracle.bmc.logging.responses.CreateLogResponse;
import com.oracle.bmc.logging.responses.ListLogGroupsResponse;
import com.oracle.bmc.logging.responses.ListLogsResponse;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import javax.annotation.Resource;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Date;
import java.util.List;
import java.util.concurrent.ThreadPoolExecutor;

import static com.doubledimple.ociserver.utils.oracle.OciUtils.getProvider;
import static com.doubledimple.ociserver.utils.oracle.OciUtils.getProviderInner;
import static com.doubledimple.ociserver.utils.oracle.OciUtils.queryRegions;
import com.doubledimple.ociserver.config.ProxyContext;

/**
 * @author doubleDimple
 * @date 2024:11:03日 13:15
 */
@Service
@Slf4j
public class OciClassLoader {

    @Resource
    private ThreadPoolExecutor threadPoolExecutor;

    public OciClassLoaderPojo loadOci(Tenant tenant){
        return doGen(tenant);
    }

    public OciClassLoaderPojo loadOci(User user){
        Tenant tenant = new Tenant();
        tenant.setUserName(user.getUserName());
        tenant.setTenantId(user.getUserId());
        tenant.setFingerprint(user.getFingerprint());
        tenant.setKeyFile(user.getKeyFile());
        tenant.setRegion(user.getRegion());
        tenant.setTenancy(user.getTenancy());
        return doGen(tenant);
    }


    private OciClassLoaderPojo doGen(Tenant tenant) {
        return OciClassLoaderPojo.builder()
                .authenticationDetailsProvider(getProvider(tenant))
                .tenant(tenant)
                .build();
    }



    /**
    * 内部读取文件调用(绝对文件路径)
    */
    public TenancyDetail loadManyRegionsInner(Tenant tenant){
        SimpleAuthenticationDetailsProvider provider = getProviderInner(tenant);
        return loadTenancyDetail(tenant,provider);
    }
    /**
    * 加载租户的多个区域,过滤掉主区域
    */
    public TenancyDetail loadManyRegions(Tenant tenant){
         SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
         return loadTenancyDetail(tenant,provider);
    }

    private TenancyDetail loadTenancyDetail(Tenant tenant,SimpleAuthenticationDetailsProvider provider){
        TenancyDetail tenancyDetail = new TenancyDetail();
        List<RegionSubscription> nonHomeRegions = new ArrayList<>();
        String tenantId = provider.getTenantId();
        if (null == tenantId) tenantId = tenant.getTenancy();
        try(Identity identityClient = IdentityClient.builder().clientConfigurator(ProxyContext.get()).build(provider);
            ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(provider)
        ){

            // 获取租户详情
            GetTenancyRequest getTenancyRequest = GetTenancyRequest.builder()
                    .tenancyId(tenantId)
                    .build();

            GetTenancyResponse response = identityClient.getTenancy(getTenancyRequest);


            // 租户名称
            String tenancyName = response.getTenancy().getName();
            String description = response.getTenancy().getDescription();

            nonHomeRegions = queryRegions(provider);
            log.debug("当前租户获取的区域为:{}", JSONUtil.toJsonStr(nonHomeRegions));

            // 尝试获取根compartment的信息
            try {
                GetCompartmentRequest compartmentRequest = GetCompartmentRequest.builder()
                        .compartmentId(provider.getTenantId()) // 根compartment的ID通常等于tenantId
                        .build();

                GetCompartmentResponse compartmentResponse = identityClient.getCompartment(compartmentRequest);
                Date creationDate = compartmentResponse.getCompartment().getTimeCreated();

                // 检查账号是否超过1个月
                Calendar oneMonthAgo = Calendar.getInstance();
                oneMonthAgo.add(Calendar.MONTH, -1);
                boolean isOlderThanOneMonth = creationDate.before(oneMonthAgo.getTime());

                log.debug("账号创建时间: " + creationDate);
                log.debug("账号注册时间是否超过1个月: " + (isOlderThanOneMonth ? "是" : "否"));

                // 查询AMD形状
                boolean canCreateLargerAMD = false;

                ListShapesRequest shapesRequest = ListShapesRequest.builder()
                        .compartmentId(provider.getTenantId())
                        .build();

                ListShapesResponse shapesResponse = computeClient.listShapes(shapesRequest);

                for (Shape shape : shapesResponse.getItems()) {
                    String shapeName = shape.getShape().toLowerCase();
                    // 是否可以开E3
                    if (shapeName.equals(ArchitectureEnum.AMD_PAID_E3.getShapeDetail().toLowerCase()) ||
                            shapeName.equals(ArchitectureEnum.AMD_PAID_E4.getShapeDetail().toLowerCase()) ||
                            shapeName.equals(ArchitectureEnum.AMD_PAID_E5.getShapeDetail().toLowerCase())) {

                        if (shape.getMemoryInGBs() != null && shape.getMemoryInGBs() > 1.0f) {
                            canCreateLargerAMD = true;
                            break;
                        }
                    }
                }

                // 结论
                if (canCreateLargerAMD && isOlderThanOneMonth) {
                    log.debug("该账号可以创建MEMORY大于1的AMD实例且注册时间超过1个月");
                    log.debug("这是一个升级账号");
                    tenancyDetail.setAccountTypeEnum(AccountTypeEnum.UPGRADE_ACCOUNT);
                } else if (canCreateLargerAMD && !isOlderThanOneMonth) {
                    tenancyDetail.setAccountTypeEnum(AccountTypeEnum.TRIAL_PAID_ACCOUNT);
                } else {
                    tenancyDetail.setAccountTypeEnum(AccountTypeEnum.FREE_ACCOUNT);
                }
            } catch (Exception e) {
                log.error("获取根compartment信息失败,原因为:{}",e.getMessage());
            }
            tenancyDetail.setRegionSubscriptions(nonHomeRegions);
            tenancyDetail.setTenancyName(tenancyName);
            tenancyDetail.setDescription(description);
        }catch (Exception e){
            log.error("加载区域失败,原因为:{}",e.getMessage());
        }
        return tenancyDetail;
    }
}
