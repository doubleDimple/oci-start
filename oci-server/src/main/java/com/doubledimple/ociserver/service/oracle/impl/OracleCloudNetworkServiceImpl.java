package com.doubledimple.ociserver.service.oracle.impl;

import cn.hutool.core.bean.BeanUtil;
import com.doubledimple.dao.entity.InstanceCloudNetWork;
import com.doubledimple.dao.repository.InstanceCloudNetworkRepository;
import com.doubledimple.ocicommon.enums.RegionEnum;
import com.doubledimple.ociserver.pojo.domain.dto.User;
import com.doubledimple.ociserver.service.oracle.OracleCloudNetworkService;
import com.doubledimple.ociserver.utils.oracle.OciUtils;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.core.VirtualNetworkClient;
import com.oracle.bmc.logging.LoggingManagementClient;
import lombok.extern.slf4j.Slf4j;
import org.springframework.cache.Cache;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.CollectionUtils;

import javax.annotation.Resource;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

import static com.doubledimple.ocicommon.cache.CacheConstants.OCI_NET_WORK_CACHE;
import static com.doubledimple.ocicommon.cache.CacheConstants.OCI_NET_WORK_KEY;
import static com.doubledimple.ocicommon.cache.CacheConstants.OCI_USER_LIST_CACHE;
import static com.doubledimple.ocicommon.cache.CacheConstants.OCI_USER_LIST_KEY;
import static com.doubledimple.ociserver.utils.oracle.OciCliUtils.createVcnAndFlowLogs;
import static com.doubledimple.ociserver.utils.oracle.OciUtils.checkShapes;
import static com.doubledimple.ociserver.utils.oracle.OciUtils.getProvider;

/**
 * 实例的网络服务层
 */
@Service
@Transactional
@Slf4j
public class OracleCloudNetworkServiceImpl implements OracleCloudNetworkService {

    @Resource
    private InstanceCloudNetworkRepository instanceCloudNetworkRepository;

    @Override
    public InstanceCloudNetWork save(InstanceCloudNetWork network) {
        return instanceCloudNetworkRepository.save( network );
    }

    @Override
    public void saveBatch(List<InstanceCloudNetWork> networks) {
        if (!CollectionUtils.isEmpty( networks )){
            List<InstanceCloudNetWork> addList = new ArrayList<>();
            for (InstanceCloudNetWork network : networks) {
                InstanceCloudNetWork netWorkAdd = new InstanceCloudNetWork();
                //查询vcnid,subnetid 的记录是否存在,如果不存在,就新增,否则更新
                String tenantId = network.getTenantId();
                String vcnId = network.getVcnId();
                String region = network.getRegion();
                String subnetId = network.getSubnetId();
                Optional<InstanceCloudNetWork> optional = instanceCloudNetworkRepository.findByTenantIdAndVcnIdAndRegionAndSubnetId(tenantId, vcnId, region, subnetId);
                if (!optional.isPresent()){
                    BeanUtil.copyProperties(network,netWorkAdd);
                    addList.add(netWorkAdd);
                }
            }

            if (!CollectionUtils.isEmpty(addList) ){
                instanceCloudNetworkRepository.saveAll(addList);
            }
        }
    }

    @Override
    public InstanceCloudNetWork findByMultipleConditions(String tenantId, String region) {
        Optional<InstanceCloudNetWork> firstByConditions = instanceCloudNetworkRepository.findFirstByConditions(tenantId, region);
        return firstByConditions.orElse(null);
    }

    @Override
    public InstanceCloudNetWork findFirstByTenantIdAndRegionOrderByCreatedAtDesc(String tenantId, String region) {
        Optional<InstanceCloudNetWork> firstByTenantIdAndRegionOrderByCreatedAtDesc = instanceCloudNetworkRepository.findFirstByTenantIdAndRegionOrderByCreatedAtDesc(tenantId, region);
        return firstByTenantIdAndRegionOrderByCreatedAtDesc.orElse(null);
    }

    /**
    * 加载网络管理器相关
    */
    @Override
    public InstanceCloudNetWork loadNetWork(User user, SimpleAuthenticationDetailsProvider provider) {
        String tenantId = user.getUserId();
        String regionCode = RegionEnum.getRegionCode(user.getRegion());
        String suffix = tenantId + "_" + regionCode;

        //直接去db查询
        return queryDb(user,null,suffix);

    }

    private InstanceCloudNetWork queryDb(User user,Cache cache,String suffix) {
        InstanceCloudNetWork instanceCloudNetWork = findFirstByTenantIdAndRegionOrderByCreatedAtDesc(user.getUserId(), RegionEnum.getRegionCode(user.getRegion()));
        if (null != instanceCloudNetWork){
            //数据库里查询的需要check,如果失效或者不存在,需要重新生成,并删除数据库的network
            boolean flag = OciUtils.checkVcnAndSubnet(user,instanceCloudNetWork.getVcnId(),instanceCloudNetWork.getSubnetId());
            if (!flag){
                List<InstanceCloudNetWork> instanceCloudNetWorkList = doCreateCloudNetWork(user);
                return instanceCloudNetWorkList.get(0);
            }else{
                return instanceCloudNetWork;
            }
        }else{
            List<InstanceCloudNetWork> instanceCloudNetWorkList = doCreateCloudNetWork(user);
            saveBatch(instanceCloudNetWorkList);
            return instanceCloudNetWorkList.get(0);
        }
    }


    public List<InstanceCloudNetWork> doCreateCloudNetWork(User user) {
        List<InstanceCloudNetWork> instanceCloudNetWorkList = new ArrayList<>();
        SimpleAuthenticationDetailsProvider provider = getProvider(user);
        try (VirtualNetworkClient virtualNetworkClient = VirtualNetworkClient.builder().build(provider);
             LoggingManagementClient loggingManagementClient = LoggingManagementClient.builder().build(provider);) {
             instanceCloudNetWorkList = createVcnAndFlowLogs(user.getUserId(), user.getRegion(), 1 , virtualNetworkClient, loggingManagementClient, provider.getTenantId(), 1);
        } catch (Exception e) {
            log.error("创建vcn和日志组失败:", e);
        }
        return instanceCloudNetWorkList;
    }
}
