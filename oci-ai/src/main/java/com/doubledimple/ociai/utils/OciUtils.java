package com.doubledimple.ociai.utils;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ocicommon.enums.RegionEnum;
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;

import java.io.FileInputStream;
import java.io.FileNotFoundException;

/**
 * @version 1.0.0
 * @ClassName Ociutils
 * @Description TODO
 * @Author renyx
 * @Date 2026-02-01 09:34
 */
public class OciUtils {

    public static SimpleAuthenticationDetailsProvider getProvider(Tenant tenant) {

        return SimpleAuthenticationDetailsProvider.builder()
                .userId(tenant.getTenantId())
                .fingerprint(tenant.getFingerprint())
                .tenantId(tenant.getTenancy())
                .privateKeySupplier(() -> {
                    try {
                        return new FileInputStream(tenant.getKeyFile());
                    } catch (FileNotFoundException e) {
                        e.printStackTrace();
                        return null;
                    }
                })
                .region(Region.fromRegionId(RegionEnum.getRegionCode(tenant.getRegion()))).build();
    }
}
