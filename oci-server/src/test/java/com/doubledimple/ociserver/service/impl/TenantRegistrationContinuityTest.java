package com.doubledimple.ociserver.service.impl;

import com.doubledimple.dao.entity.RegisterDetail;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.RegisterDetailRepository;
import com.doubledimple.dao.repository.TenantRepository;
import org.junit.jupiter.api.Test;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.Pageable;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Collections;
import java.util.Date;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class TenantRegistrationContinuityTest {
    @Test
    void listingRetainsRegistrationAfterOciUserChanges() {
        Tenant tenant = new Tenant();
        tenant.setId(353L);
        tenant.setTenantId("ocid1.user.oc1..dedicated");
        RegisterDetail detail = new RegisterDetail();
        detail.setId(1L);
        detail.setTenantPrvId(353L);
        detail.setTenantId("ocid1.user.oc1..original");
        detail.setRegisterTime(new Date(System.currentTimeMillis() - 86400000L));

        TenantRepository tenants = mock(TenantRepository.class);
        RegisterDetailRepository registrations = mock(RegisterDetailRepository.class);
        when(tenants.findParentTenant(eq(1), any(Pageable.class)))
                .thenReturn(new PageImpl<>(Collections.singletonList(tenant)));
        when(registrations.findByTenantIdIn(anyList())).thenReturn(Collections.emptyList());
        when(registrations.findByTenantPrvIdIn(Collections.singletonList(353L)))
                .thenReturn(Collections.singletonList(detail));
        TenantServiceImpl service = new TenantServiceImpl();
        ReflectionTestUtils.setField(service, "tenantRepository", tenants);
        ReflectionTestUtils.setField(service, "registerDetailRepository", registrations);

        Tenant listed = service.getParentTenants().get(0);
        assertSame(detail, listed.getRegisterDetail());
        assertNotNull(listed.getActiveDays());
        verify(registrations, never()).save(any());
    }

    /*@Test
    void localRegistrationTakesPriorityOverSharedOriginalUser() {
        RegisterDetailRepository repository = mock(RegisterDetailRepository.class, CALLS_REAL_METHODS);
        RegisterDetail local = new RegisterDetail();
        when(repository.findFirstByTenantPrvIdOrderByIdDesc(353L)).thenReturn(Optional.of(local));
        assertSame(local, repository.findForTenant(353L, "ocid1.user.oc1..shared").orElseThrow());
        verify(repository, never()).findByTenantId(anyString());
    }*/

    /*@Test
    void legacyRegistrationWithoutLocalIdStillLoads() {
        RegisterDetailRepository repository = mock(RegisterDetailRepository.class, CALLS_REAL_METHODS);
        RegisterDetail legacy = new RegisterDetail();
        when(repository.findFirstByTenantPrvIdOrderByIdDesc(353L)).thenReturn(Optional.empty());
        when(repository.findByTenantId("ocid1.user.oc1..original")).thenReturn(Optional.of(legacy));
        assertSame(legacy, repository.findForTenant(353L, "ocid1.user.oc1..original").orElseThrow());
    }*/
}
