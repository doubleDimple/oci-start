package com.doubledimple.ociserver.controller;

import com.doubledimple.ociserver.service.TenantService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.util.Arrays;

import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

class RegionResourcesControllerTest {
    private TenantService service;
    private MockMvc mvc;

    @BeforeEach void setUp() {
        service = mock(TenantService.class);
        RegionResourcesController controller = new RegionResourcesController();
        ReflectionTestUtils.setField(controller, "tenantService", service);
        mvc = MockMvcBuilders.standaloneSetup(controller).build();
    }

    @Test void exposesOnlyLocalAccountAssociationsAndRegionNames() throws Exception {
        when(service.listOwnedOciRegions()).thenReturn(Arrays.asList("ap-tokyo-1", "future-region-1"));
        mvc.perform(get("/resource/my-regions")).andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.data.hasRecords[0].region").value("ap-tokyo-1"))
                .andExpect(jsonPath("$.data.hasRecords[1].region").value("future-region-1"))
                .andExpect(jsonPath("$.data.regionMap['ap-tokyo-1']").isString());
        verify(service).listOwnedOciRegions();
        verifyNoMoreInteractions(service);
    }

    @Test void failedReadsRemainFailuresWithoutExposingInternalDetails() throws Exception {
        when(service.listOwnedOciRegions()).thenThrow(new IllegalStateException("PRIVATE_DATABASE_DETAIL"));
        mvc.perform(get("/resource/my-regions")).andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.data").isEmpty())
                .andExpect(content().string(not(containsString("PRIVATE_DATABASE_DETAIL"))));
    }
}
