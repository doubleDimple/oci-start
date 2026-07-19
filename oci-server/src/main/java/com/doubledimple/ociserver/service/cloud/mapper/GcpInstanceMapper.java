package com.doubledimple.ociserver.service.cloud.mapper;

import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.ocicommon.enums.CloudTypeEnum;
import com.doubledimple.ocicommon.enums.gcp.GcpMachineTypeEnum;
import com.doubledimple.ociserver.pojo.gcp.InstanceInfo;
import org.apache.commons.lang3.StringUtils;

import java.util.List;

/**
 * GCP InstanceInfo → 中立 InstanceDetails。
 */
public final class GcpInstanceMapper {

    private GcpInstanceMapper() {
    }

    public static InstanceDetails toInstanceDetails(InstanceInfo info, long tenantId, String projectId) {
        if (info == null) {
            return null;
        }
        InstanceDetails d = new InstanceDetails();
        d.setTenantId(tenantId);
        d.setCloudType(CloudTypeEnum.GOOGLE_CLOUD.getType());

        String zone = extractLastSegment(info.getZone());
        String name = info.getName();
        // 稳定 instanceId：优先 GCP 数字 id，否则 zone/name
        if (StringUtils.isNotBlank(info.getId())) {
            d.setInstanceId(info.getId());
        } else {
            d.setInstanceId(zone + "/" + name);
        }
        d.setDisplayName(name);
        d.setAvailabilityDomain(zone);
        d.setCompartmentId(projectId == null ? null : "projects/" + projectId);
        d.setState(info.getStatus() == null ? "UNKNOWN" : info.getStatus().toUpperCase());

        String machineType = extractLastSegment(info.getMachineType());
        d.setShape(machineType);
        fillCpuMemory(d, machineType);

        d.setPublicIps(nullToEmpty(info.getExternalIP()));
        d.setPrivateIps(nullToEmpty(info.getInternalIP()));
        d.setBootVolumeSizeInGBs((long) parseDiskSize(info.getDisks()));
        d.setArchitecture(extractArchitecture(info));
        d.setProcessorDescription(info.getCpuPlatform() == null ? "NONE" : info.getCpuPlatform());
        d.setUsername("root");
        d.setPort(22);
        d.setPassword("");
        if (info.getDisks() != null) {
            for (InstanceInfo.Disk disk : info.getDisks()) {
                if (Boolean.TRUE.equals(disk.getBoot()) && StringUtils.isNotBlank(disk.getSource())) {
                    d.setBootVolumeId(disk.getSource());
                    break;
                }
            }
        }
        return d;
    }

    private static void fillCpuMemory(InstanceDetails d, String machineType) {
        if (StringUtils.isBlank(machineType)) {
            d.setOcpus(1);
            d.setMemoryInGBs(1);
            return;
        }
        if (machineType.startsWith("custom-")) {
            // custom-{cpu}-{mb}
            String[] parts = machineType.replace("custom-", "").split("-");
            if (parts.length >= 2) {
                try {
                    d.setOcpus(Integer.parseInt(parts[0]));
                    d.setMemoryInGBs(Math.max(1, Integer.parseInt(parts[1]) / 1024));
                    return;
                } catch (NumberFormatException ignored) {
                }
            }
        }
        GcpMachineTypeEnum mt = GcpMachineTypeEnum.getByName(machineType);
        if (mt != null) {
            d.setOcpus((int) Math.ceil(mt.getVCpuCount()));
            d.setMemoryInGBs((int) Math.ceil(mt.getMemoryGb()));
            return;
        }
        d.setOcpus(1);
        d.setMemoryInGBs(1);
    }

    private static int parseDiskSize(List<InstanceInfo.Disk> disks) {
        if (disks == null || disks.isEmpty()) {
            return 20;
        }
        for (InstanceInfo.Disk disk : disks) {
            if (Boolean.TRUE.equals(disk.getBoot()) && disk.getDiskSizeGb() != null) {
                try {
                    return Integer.parseInt(disk.getDiskSizeGb());
                } catch (NumberFormatException ignored) {
                }
            }
        }
        if (disks.get(0).getDiskSizeGb() != null) {
            try {
                return Integer.parseInt(disks.get(0).getDiskSizeGb());
            } catch (NumberFormatException ignored) {
            }
        }
        return 20;
    }

    private static String extractArchitecture(InstanceInfo info) {
        if (info.getMachineType() != null && info.getMachineType().contains("arm")) {
            return "ARM64";
        }
        if (info.getCpuPlatform() != null && info.getCpuPlatform().toLowerCase().contains("ampere")) {
            return "ARM64";
        }
        return "X86_64";
    }

    public static String extractLastSegment(String urlOrName) {
        if (urlOrName == null || urlOrName.isEmpty()) {
            return "";
        }
        int idx = urlOrName.lastIndexOf('/');
        return idx >= 0 ? urlOrName.substring(idx + 1) : urlOrName;
    }

    private static String nullToEmpty(String s) {
        return s == null ? "" : s;
    }
}
