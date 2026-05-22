package com.doubledimple.ociserver.service.impl;

import com.doubledimple.dao.entity.VpnProxyRecord;
import com.doubledimple.dao.repository.VpnProxyRecordRepository;
import com.doubledimple.ociserver.pojo.request.VpnProxyRecordRequest;
import com.doubledimple.ociserver.service.VpnProxyRecordService;
import com.doubledimple.ociserver.utils.PageUtils;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.BeanUtils;
import org.springframework.data.domain.Page;
import org.springframework.data.jpa.domain.Specification;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import javax.annotation.Resource;
import javax.persistence.criteria.Predicate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

/**
 * @version 1.0.0
 * @ClassName VpnProxyRecordServiceImpl
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-11-01 13:42
 */
@Slf4j
@Service
public class VpnProxyRecordServiceImpl implements VpnProxyRecordService {

    @Resource
    VpnProxyRecordRepository vpnProxyRecordRepository;

    @Override
    public Page<VpnProxyRecord> listPage(VpnProxyRecordRequest request) {
        Specification<VpnProxyRecord> spec = (root, query, criteriaBuilder) -> {
            List<Predicate> predicates = new ArrayList<>();
            return criteriaBuilder.and(predicates.toArray(new Predicate[0]));
        };

        return PageUtils.findWithSpec(vpnProxyRecordRepository, request, spec);
    }

    @Override
    @Transactional
    public void saveOrUpdate(VpnProxyRecordRequest vpnProxyRecordRequest) {
        VpnProxyRecord topByProxyHost = vpnProxyRecordRepository.findTopByProxyHost(vpnProxyRecordRequest.getProxyHost());
        LocalDateTime now = LocalDateTime.now();
        if (topByProxyHost == null){
            VpnProxyRecord vpnProxyRecord = new VpnProxyRecord();
            vpnProxyRecord.setProxyHost(vpnProxyRecordRequest.getProxyHost());
            BeanUtils.copyProperties(vpnProxyRecordRequest, vpnProxyRecord);
            vpnProxyRecord.setCreateTime(now);
            vpnProxyRecord.setUpdateTime(now);
            vpnProxyRecordRepository.save(vpnProxyRecord);
        }else{
            final Long id = topByProxyHost.getId();
            BeanUtils.copyProperties(vpnProxyRecordRequest, topByProxyHost);
            topByProxyHost.setId(id);
            vpnProxyRecordRepository.save(topByProxyHost);
        }
    }

    @Override
    public List<VpnProxyRecord> queryListEnable() {
        return vpnProxyRecordRepository.findAllByAvailableStatus(1);
    }

    @Transactional
    @Override
    public void delete(VpnProxyRecordRequest vpnProxyRecordRequest) {
        vpnProxyRecordRepository.deleteById(vpnProxyRecordRequest.getId());
    }
}
