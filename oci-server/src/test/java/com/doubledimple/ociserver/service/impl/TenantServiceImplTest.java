package com.doubledimple.ociserver.service.impl;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.TenantRepository;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Arrays;
import java.util.Collections;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class TenantServiceImplTest {

    @Test
    void listsDistinctOwnedOciRegionsWithoutOtherProvidersOrBlankRegions() {
        TenantServiceImpl service = new TenantServiceImpl();
        TenantRepository repository = mock(TenantRepository.class);
        ReflectionTestUtils.setField(service, "tenantRepository", repository);
        when(repository.findAll()).thenReturn(Arrays.asList(
                tenant(1, "ap-tokyo-1"), tenant(1, "ap-tokyo-1"), tenant(1, "eu-frankfurt-1"),
                tenant(2, "us-ashburn-1"), tenant(0, "us-phoenix-1"), tenant(1, " "), tenant(1, null),
                tenant(1, "future-region-1")));
        assertEquals(Arrays.asList("ap-tokyo-1", "eu-frankfurt-1", "future-region-1"), service.listOwnedOciRegions());
        when(repository.findAll()).thenReturn(Collections.emptyList());
        assertEquals(Collections.emptyList(), service.listOwnedOciRegions());
    }

    private static Tenant tenant(Integer cloudType, String region) {
        Tenant tenant = new Tenant();
        tenant.setCloudType(cloudType); tenant.setRegion(region);
        return tenant;
    }

    @Test
    void rejectsPasswordExpiryDaysBelowZero() {
        TenantServiceImpl service = new TenantServiceImpl();

        assertThrows(IllegalArgumentException.class,
                () -> service.updateUserPasswordPolicy("1", true, -1));
    }

    @Test
    void rejectsPasswordExpiryDaysAbove365() {
        TenantServiceImpl service = new TenantServiceImpl();

        assertThrows(IllegalArgumentException.class,
                () -> service.updateUserPasswordPolicy("1", true, 366));
    }
}
