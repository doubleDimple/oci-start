package com.doubledimple.ociserver.service;

import com.doubledimple.dao.entity.BootInstance;
import com.doubledimple.ociserver.pojo.domain.query.BootInstanceQuery;
import com.doubledimple.ociserver.pojo.request.ImageInfoReq;
import com.doubledimple.ociserver.pojo.request.UpdateBootInstanceRequest;
import com.doubledimple.ociserver.pojo.response.ImageInfoRes;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.pojo.response.BootInstanceRes;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;

import java.util.List;

public interface BootInstanceService {

    void saveBootInstance(BootInstance bootInstance);

    List<BootInstance> getAllTenants(long tenantId);

    void startInstance(BootInstance bootInstance);

    void stopBoot(BootInstance bootInstance);

    void autoStopBoot(BootInstance bootInstance,String err);

    void deleteBoot(BootInstance bootInstance);

    Page<BootInstanceRes> getAllBoots(int page, int size);

    /**
     * 支持分页的模糊查询
     * @param query
     * @param pageable
     * @return
     */
    Page<BootInstanceRes> findBootInstances(BootInstanceQuery query, Pageable pageable);

    ApiResponse updateBootInstance(UpdateBootInstanceRequest request);

    long countByStatus(int i);

    Page<BootInstanceRes> getBootsByTenantId(String tenantId, int page, int size);

    //查询系统镜像
    List<ImageInfoRes> querySystemImage(ImageInfoReq imageInfoReq);

    void batchInitFailCount();


    Page<BootInstanceRes> findAllWithTenantInfo(String tenantId, Pageable pageable);


}
