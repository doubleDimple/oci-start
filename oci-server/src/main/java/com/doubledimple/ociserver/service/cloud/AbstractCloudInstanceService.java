package com.doubledimple.ociserver.service.cloud;

import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.OracleInstanceDetailRepository;
import com.doubledimple.dao.repository.TenantRepository;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.CollectionUtils;

import javax.annotation.Resource;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * 同步模板：远程 list + 本地 upsert/merge。
 * 各云只需实现 listRemote 与操作方法。
 */
@Slf4j
public abstract class AbstractCloudInstanceService implements CloudInstanceService {

    @Resource
    protected OracleInstanceDetailRepository instanceDetailRepository;

    @Resource
    protected TenantRepository tenantRepository;

    @Override
    @Transactional(rollbackFor = Exception.class)
    public void syncToLocal(Tenant tenant) {
        try {
            List<InstanceDetails> remoteList = listRemote(tenant);
            if (remoteList == null) {
                remoteList = new ArrayList<InstanceDetails>();
            }
            remoteList = filterValid(remoteList);

            List<InstanceDetails> localList = instanceDetailRepository.findByTenantId(tenant.getId());
            Map<String, InstanceDetails> localByCloudId = new HashMap<String, InstanceDetails>();
            if (!CollectionUtils.isEmpty(localList)) {
                for (InstanceDetails local : localList) {
                    if (StringUtils.isNotBlank(local.getInstanceId())) {
                        localByCloudId.put(local.getInstanceId(), local);
                    }
                }
            }

            Set<String> remoteIds = new HashSet<String>();
            List<InstanceDetails> toSave = new ArrayList<InstanceDetails>();

            for (InstanceDetails remote : remoteList) {
                remote.setTenantId(tenant.getId());
                remote.setCloudType(getCloudType().getType());
                remoteIds.add(remote.getInstanceId());

                InstanceDetails existing = localByCloudId.get(remote.getInstanceId());
                if (existing != null) {
                    mergeLocalFields(existing, remote);
                    toSave.add(existing);
                } else {
                    // 兼容：按 displayName 找回本地密码（OTHER 迁移场景）
                    InstanceDetails byName = findLocalByDisplayName(localList, remote.getDisplayName());
                    if (byName != null && !remoteIds.contains(byName.getInstanceId())) {
                        mergeLocalFields(byName, remote);
                        byName.setInstanceId(remote.getInstanceId());
                        toSave.add(byName);
                    } else {
                        toSave.add(remote);
                    }
                }
            }

            // 删除云端已不存在的本地记录（同租户）
            if (!CollectionUtils.isEmpty(localList)) {
                for (InstanceDetails local : localList) {
                    if (StringUtils.isBlank(local.getInstanceId()) || !remoteIds.contains(local.getInstanceId())) {
                        instanceDetailRepository.delete(local);
                    }
                }
            }

            if (!toSave.isEmpty()) {
                instanceDetailRepository.saveAllAndFlush(toSave);
            }

            tenant.setApiSynced(true);
            tenantRepository.save(tenant);
            log.info("租户[{}] {} 实例同步完成，远程{}条", tenant.getId(), getCloudType(), remoteList.size());
        } catch (Exception e) {
            log.error("租户[{}] {} 实例同步失败", tenant.getId(), getCloudType(), e);
            if (e instanceof RuntimeException) {
                throw (RuntimeException) e;
            }
            throw new RuntimeException("同步实例失败: " + e.getMessage(), e);
        }
    }

    protected List<InstanceDetails> filterValid(List<InstanceDetails> list) {
        List<InstanceDetails> result = new ArrayList<InstanceDetails>();
        for (InstanceDetails d : list) {
            if (d != null && StringUtils.isNotBlank(d.getInstanceId())) {
                result.add(d);
            }
        }
        return result;
    }

    /**
     * 将远程字段覆盖到本地实体，保留本地 SSH/备注/监控等。
     */
    protected void mergeLocalFields(InstanceDetails local, InstanceDetails remote) {
        String password = local.getPassword();
        String username = local.getUsername();
        Integer port = local.getPort();
        String remark = local.getRemark();
        Integer enablePing = local.getEnablePing();
        Integer onLineEnable = local.getOnLineEnable();
        Integer lastOnLineEnable = local.getLastOnLineEnable();
        Integer offlineNotify = local.getOfflineNotify();
        Integer resumeNotify = local.getResumeNotify();
        Boolean monitorInstalled = local.getMonitorInstalled();
        java.util.Date lastHeartbeat = local.getLastHeartbeat();
        Long connTime = local.getConnTime();
        int sysImageBackup = local.getSysImageBackup();

        local.setDisplayName(remote.getDisplayName());
        local.setShape(remote.getShape());
        local.setState(remote.getState());
        local.setOcpus(remote.getOcpus());
        local.setMemoryInGBs(remote.getMemoryInGBs());
        local.setBootVolumeSizeInGBs(remote.getBootVolumeSizeInGBs());
        local.setPublicIps(remote.getPublicIps());
        local.setPrivateIps(remote.getPrivateIps());
        local.setAvailabilityDomain(remote.getAvailabilityDomain());
        local.setCompartmentId(remote.getCompartmentId());
        local.setBootVolumeId(remote.getBootVolumeId());
        local.setArchitecture(remote.getArchitecture());
        local.setProcessorDescription(remote.getProcessorDescription());
        local.setIpv6Addresses(remote.getIpv6Addresses());
        local.setVnicIds(remote.getVnicIds());
        local.setCloudType(remote.getCloudType());
        local.setInstanceId(remote.getInstanceId());

        // 远程若带了密码且本地为空，则用远程
        if (StringUtils.isNotBlank(password)) {
            local.setPassword(password);
        } else if (StringUtils.isNotBlank(remote.getPassword())) {
            local.setPassword(remote.getPassword());
        }
        if (StringUtils.isNotBlank(username)) {
            local.setUsername(username);
        } else if (StringUtils.isNotBlank(remote.getUsername())) {
            local.setUsername(remote.getUsername());
        } else {
            local.setUsername(defaultUsername());
        }
        if (port != null) {
            local.setPort(port);
        }
        if (StringUtils.isNotBlank(remark)) {
            local.setRemark(remark);
        } else if (StringUtils.isNotBlank(remote.getRemark())) {
            local.setRemark(remote.getRemark());
        }
        if (enablePing != null) {
            local.setEnablePing(enablePing);
        }
        if (onLineEnable != null) {
            local.setOnLineEnable(onLineEnable);
        }
        if (lastOnLineEnable != null) {
            local.setLastOnLineEnable(lastOnLineEnable);
        }
        if (offlineNotify != null) {
            local.setOfflineNotify(offlineNotify);
        }
        if (resumeNotify != null) {
            local.setResumeNotify(resumeNotify);
        }
        if (monitorInstalled != null) {
            local.setMonitorInstalled(monitorInstalled);
        }
        if (lastHeartbeat != null) {
            local.setLastHeartbeat(lastHeartbeat);
        }
        if (connTime != null) {
            local.setConnTime(connTime);
        }
        local.setSysImageBackup(sysImageBackup);
    }

    protected String defaultUsername() {
        return "";
    }

    private InstanceDetails findLocalByDisplayName(List<InstanceDetails> localList, String displayName) {
        if (CollectionUtils.isEmpty(localList) || StringUtils.isBlank(displayName)) {
            return null;
        }
        for (InstanceDetails local : localList) {
            if (displayName.equals(local.getDisplayName())) {
                return local;
            }
        }
        return null;
    }

    protected void requireCapability(boolean supported, String op) {
        if (!supported) {
            throw new UnsupportedOperationException(getCloudType() + " 不支持操作: " + op);
        }
    }
}
