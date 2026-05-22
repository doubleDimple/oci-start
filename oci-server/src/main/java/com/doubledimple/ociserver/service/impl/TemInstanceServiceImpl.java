package com.doubledimple.ociserver.service.impl;

import com.doubledimple.dao.entity.TemInstance;
import com.doubledimple.dao.repository.TemInstanceRepository;
import com.doubledimple.ociserver.service.TemInstanceService;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import javax.annotation.Resource;
import java.util.List;

/**
 * @version 1.0.0
 * @ClassName TemInstanceServiceImpl
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-03-27 16:43
 */
@Service
@Slf4j
public class TemInstanceServiceImpl implements TemInstanceService {

    @Resource
    private TemInstanceRepository temInstanceRepository;

    @Transactional
    @Override
    public void deleteByTenancyAndRegionAndArchitecture(String tenancy, String regions, String type, SimpleAuthenticationDetailsProvider provider, String tmpInstanceId,boolean deleteInsFlag) {
        log.debug("开始删除临时实例,请求参数是,tenancy:{},regions:{},type:{}", tenancy, regions, type);
        temInstanceRepository.deleteByTenancyAndRegionAndArchitecture(tenancy, regions, type);
        //是否需要删除临时实例 false:不删除,  true:删除
        if (deleteInsFlag){
            //todo 暂时不终止实例
            //OciUtils.terminateInstance(provider, tmpInstanceId,false);
        }
    }

    @Override
    public List<TemInstance> findByTenancyAndRegionAndArchitecture(String tenancy, String region, String type) {
        return temInstanceRepository.findByTenancyAndRegionAndArchitecture(tenancy, region, type);
    }

    @Transactional
    @Override
    @Async
    public void save(TemInstance temInstance) {
        temInstanceRepository.save(temInstance);
    }

    @Override
    public TemInstance findByInstanceId(String instanceId) {
        return temInstanceRepository.findByInstanceId(instanceId);
    }

    @Override
    @Transactional
    public void deleteByTenancy(String tenancy, String regions, String type) {
        log.debug("开始删除临时实例,请求参数是,tenancy:{},regions:{},type:{}", tenancy, regions, type);
        temInstanceRepository.deleteByTenancyAndRegionAndArchitecture(tenancy, regions, type);
    }
}
