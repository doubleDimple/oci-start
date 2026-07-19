package com.doubledimple.ociserver.service.cloud;

import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

/**
 * 中立创建实例命令。各云共有字段 + extras 承载厂商特有参数。
 */
public class CreateInstanceCommand {

    private String instanceName;
    private String region;
    private String zone;
    private String machineType;
    private Integer cpuCount;
    private Integer memoryGb;
    private Integer diskSizeGb;
    private Integer instanceCount = 1;
    private String imageRef;
    private String rootPassword;
    private Boolean customMachine = Boolean.FALSE;
    private Map<String, String> extras = new HashMap<String, String>();

    public String getInstanceName() {
        return instanceName;
    }

    public void setInstanceName(String instanceName) {
        this.instanceName = instanceName;
    }

    public String getRegion() {
        return region;
    }

    public void setRegion(String region) {
        this.region = region;
    }

    public String getZone() {
        return zone;
    }

    public void setZone(String zone) {
        this.zone = zone;
    }

    public String getMachineType() {
        return machineType;
    }

    public void setMachineType(String machineType) {
        this.machineType = machineType;
    }

    public Integer getCpuCount() {
        return cpuCount;
    }

    public void setCpuCount(Integer cpuCount) {
        this.cpuCount = cpuCount;
    }

    public Integer getMemoryGb() {
        return memoryGb;
    }

    public void setMemoryGb(Integer memoryGb) {
        this.memoryGb = memoryGb;
    }

    public Integer getDiskSizeGb() {
        return diskSizeGb;
    }

    public void setDiskSizeGb(Integer diskSizeGb) {
        this.diskSizeGb = diskSizeGb;
    }

    public Integer getInstanceCount() {
        return instanceCount;
    }

    public void setInstanceCount(Integer instanceCount) {
        this.instanceCount = instanceCount;
    }

    public String getImageRef() {
        return imageRef;
    }

    public void setImageRef(String imageRef) {
        this.imageRef = imageRef;
    }

    public String getRootPassword() {
        return rootPassword;
    }

    public void setRootPassword(String rootPassword) {
        this.rootPassword = rootPassword;
    }

    public Boolean getCustomMachine() {
        return customMachine;
    }

    public void setCustomMachine(Boolean customMachine) {
        this.customMachine = customMachine;
    }

    public Map<String, String> getExtras() {
        return extras == null ? Collections.<String, String>emptyMap() : extras;
    }

    public void setExtras(Map<String, String> extras) {
        this.extras = extras == null ? new HashMap<String, String>() : extras;
    }

    public void putExtra(String key, String value) {
        if (this.extras == null) {
            this.extras = new HashMap<String, String>();
        }
        this.extras.put(key, value);
    }

    public String getExtra(String key) {
        return extras == null ? null : extras.get(key);
    }
}
