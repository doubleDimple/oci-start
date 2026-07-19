package com.doubledimple.ociserver.service.cloud;

/**
 * 云厂商能力声明。UI/API 按能力裁剪操作，避免对每云写死 if-else。
 * 新增云时在静态工厂方法中声明即可。
 */
public final class CloudCapability {

    private final boolean listSync;
    private final boolean startStop;
    private final boolean reboot;
    private final boolean terminate;
    private final boolean changePublicIp;
    private final boolean createDirect;
    private final boolean retryLaunchJob;
    private final boolean ipv6;
    private final boolean multiVnic;
    private final boolean bootVolumeResize;

    private CloudCapability(Builder b) {
        this.listSync = b.listSync;
        this.startStop = b.startStop;
        this.reboot = b.reboot;
        this.terminate = b.terminate;
        this.changePublicIp = b.changePublicIp;
        this.createDirect = b.createDirect;
        this.retryLaunchJob = b.retryLaunchJob;
        this.ipv6 = b.ipv6;
        this.multiVnic = b.multiVnic;
        this.bootVolumeResize = b.bootVolumeResize;
    }

    public static CloudCapability oci() {
        return new Builder()
                .listSync(true)
                .startStop(true)
                .reboot(true)
                .terminate(true)
                .changePublicIp(true)
                .createDirect(false)
                .retryLaunchJob(true)
                .ipv6(true)
                .multiVnic(true)
                .bootVolumeResize(true)
                .build();
    }

    public static CloudCapability gcp() {
        return new Builder()
                .listSync(true)
                .startStop(true)
                .reboot(true)
                .terminate(true)
                .changePublicIp(true)
                .createDirect(true)
                .retryLaunchJob(false)
                .ipv6(false)
                .multiVnic(false)
                .bootVolumeResize(false)
                .build();
    }

    public static Builder builder() {
        return new Builder();
    }

    public boolean isListSync() {
        return listSync;
    }

    public boolean isStartStop() {
        return startStop;
    }

    public boolean isReboot() {
        return reboot;
    }

    public boolean isTerminate() {
        return terminate;
    }

    public boolean isChangePublicIp() {
        return changePublicIp;
    }

    public boolean isCreateDirect() {
        return createDirect;
    }

    public boolean isRetryLaunchJob() {
        return retryLaunchJob;
    }

    public boolean isIpv6() {
        return ipv6;
    }

    public boolean isMultiVnic() {
        return multiVnic;
    }

    public boolean isBootVolumeResize() {
        return bootVolumeResize;
    }

    public static final class Builder {
        private boolean listSync;
        private boolean startStop;
        private boolean reboot;
        private boolean terminate;
        private boolean changePublicIp;
        private boolean createDirect;
        private boolean retryLaunchJob;
        private boolean ipv6;
        private boolean multiVnic;
        private boolean bootVolumeResize;

        public Builder listSync(boolean v) {
            this.listSync = v;
            return this;
        }

        public Builder startStop(boolean v) {
            this.startStop = v;
            return this;
        }

        public Builder reboot(boolean v) {
            this.reboot = v;
            return this;
        }

        public Builder terminate(boolean v) {
            this.terminate = v;
            return this;
        }

        public Builder changePublicIp(boolean v) {
            this.changePublicIp = v;
            return this;
        }

        public Builder createDirect(boolean v) {
            this.createDirect = v;
            return this;
        }

        public Builder retryLaunchJob(boolean v) {
            this.retryLaunchJob = v;
            return this;
        }

        public Builder ipv6(boolean v) {
            this.ipv6 = v;
            return this;
        }

        public Builder multiVnic(boolean v) {
            this.multiVnic = v;
            return this;
        }

        public Builder bootVolumeResize(boolean v) {
            this.bootVolumeResize = v;
            return this;
        }

        public CloudCapability build() {
            return new CloudCapability(this);
        }
    }
}
