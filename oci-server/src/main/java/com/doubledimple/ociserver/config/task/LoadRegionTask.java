package com.doubledimple.ociserver.config.task;

import cn.hutool.json.JSONUtil;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.ociserver.utils.oracle.OciClassLoader;
import com.doubledimple.ociserver.pojo.request.TenancyDetail;
import com.oracle.bmc.identity.model.RegionSubscription;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;

import javax.annotation.Resource;
import java.util.List;

/**
 * @version 1.0.0
 * 加载区域
 */
@Service
@Slf4j
public class LoadRegionTask {

    @Resource
    private TenantRepository tenantRepository;

    @Resource
    private OciClassLoader ociClassLoader;


    public void loadRegion() {
        Pageable pageable = PageRequest.of(0, 200);
        // 获取父记录
        Page<Tenant> parentTenants = tenantRepository.findByParenIdIsNullOrParenIdAndCloudType(0L,1, pageable);

        if (parentTenants != null && !parentTenants.getContent().isEmpty()) {
            // 处理每个父记录
            for (Tenant parent : parentTenants.getContent()) {
                if (StringUtils.isEmpty(parent.getTenancyName())){
                    try {
                        Tenant tenantUpdate = tenantRepository.findById(parent.getId())
                                .orElseThrow(() -> new RuntimeException("Tenant not found with id: " + parent.getId()));
                        TenancyDetail tenancyDetail = ociClassLoader.loadManyRegions(tenantUpdate);
                        if (StringUtils.isNotBlank(tenancyDetail.getTenancyName())){
                            tenantUpdate.setTenancyName(tenancyDetail.getTenancyName());
                        }

                        if (StringUtils.isNotBlank(tenancyDetail.getDescription())){
                            tenantUpdate.setTenancyDes(tenancyDetail.getDescription());
                        }
                        if (StringUtils.isNotBlank(tenancyDetail.getAccountTypeEnum().getType())){
                            tenantUpdate.setAccountType(tenancyDetail.getAccountTypeEnum().getType());
                        }
                        List<RegionSubscription> regionSubscriptions = tenancyDetail.getRegionSubscriptions();
                        if (regionSubscriptions.stream()
                                .anyMatch(item -> item.getRegionName().equals(parent.getRegion()))) {
                            tenantUpdate.setIsHomeRegion(true);
                        }
                        log.error("保存租户setR的信息是:{}", JSONUtil.toJsonStr(tenantUpdate));
                        tenantRepository.save(tenantUpdate);
                    } catch (Exception e) {
                        log.error("tenant 数据不存在");
                    }
                }
            }
        }
    }
}



