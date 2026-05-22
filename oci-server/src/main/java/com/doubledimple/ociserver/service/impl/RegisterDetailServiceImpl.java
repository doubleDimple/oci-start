package com.doubledimple.ociserver.service.impl;

import com.doubledimple.dao.entity.RegisterDetail;
import com.doubledimple.dao.repository.RegisterDetailRepository;
import com.doubledimple.ociserver.service.RegisterDetailService;
import com.oracle.bmc.ospgateway.model.Subscription;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import javax.annotation.Resource;
import java.time.LocalDateTime;
import java.util.Optional;

/**
 * @version 1.0.0
 * @ClassName RegisterDetailServiceImpl
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-05-24 13:42
 */
@Service
@Slf4j
public class RegisterDetailServiceImpl implements RegisterDetailService {

    @Resource
    private RegisterDetailRepository registerDetailRepository;

    @Override
    public void saveRegisterDetail(Long snowflakeNextId, String tenantId, Subscription subscription) {
        Optional<RegisterDetail> byTenantId = registerDetailRepository.findByTenantId(tenantId);
        byTenantId.ifPresent(registerDetail -> registerDetailRepository.delete(registerDetail));
        RegisterDetail registerDetail = new RegisterDetail();
        registerDetail.setTenantPrvId(snowflakeNextId);
        registerDetail.setTenantId(tenantId);
        registerDetail.setAccountType(subscription.getAccountType());
        registerDetail.setPlanType(subscription.getPlanType());
        registerDetail.setRegisterTime(subscription.getTimeStart());
        registerDetail.setCity(subscription.getBillingAddress().getCity());
        registerDetail.setCountry(subscription.getBillingAddress().getCountry());
        registerDetail.setEmailAddress(subscription.getBillingAddress().getEmailAddress());
        registerDetail.setFirstName(subscription.getBillingAddress().getFirstName());
        registerDetail.setLastName(subscription.getBillingAddress().getLastName());
        registerDetail.setLine1(subscription.getBillingAddress().getLine1());
        registerDetail.setPostalCode(subscription.getBillingAddress().getPostalCode());
        registerDetail.setSubscriptionPlanNumber(subscription.getSubscriptionPlanNumber());
        registerDetail.setUpgradeState(subscription.getUpgradeState().getValue());
        registerDetail.setCreatedTime(LocalDateTime.now());
        registerDetail.setUpdatedTime(LocalDateTime.now());
        registerDetailRepository.save(registerDetail);
    }
}
