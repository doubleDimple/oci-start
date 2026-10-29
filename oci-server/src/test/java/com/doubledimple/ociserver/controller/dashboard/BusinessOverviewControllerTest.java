package com.doubledimple.ociserver.controller.dashboard;

import com.doubledimple.ociserver.pojo.response.BusinessOverview;
import com.doubledimple.ociserver.service.dashboard.BusinessOverviewService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import static org.hamcrest.Matchers.not;
import static org.hamcrest.Matchers.containsString;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

class BusinessOverviewControllerTest {
    private BusinessOverviewService service;
    private MockMvc mvc;

    @BeforeEach void setUp() {
        service = mock(BusinessOverviewService.class);
        mvc = MockMvcBuilders.standaloneSetup(new BusinessOverviewController(service)).build();
    }

    @Test void returnsRequestedPeriodAndDoesNotCacheStatistics() throws Exception {
        BusinessOverview seven = new BusinessOverview(); seven.setDays(7);
        BusinessOverview thirty = new BusinessOverview(); thirty.setDays(30);
        when(service.overview(7)).thenReturn(seven);
        when(service.overview(30)).thenReturn(thirty);
        mvc.perform(get("/api/dashboard/business")).andExpect(status().isOk())
                .andExpect(header().string("Cache-Control", "no-store"))
                .andExpect(jsonPath("$.success").value(true)).andExpect(jsonPath("$.data.days").value(7));
        mvc.perform(get("/api/dashboard/business").param("days", "30")).andExpect(status().isOk())
                .andExpect(jsonPath("$.data.days").value(30));
        verify(service).overview(7); verify(service).overview(30);
    }

    @Test void rejectsInvalidPeriodsBeforeQueryingTheDatabase() throws Exception {
        mvc.perform(get("/api/dashboard/business").param("days", "365")).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.success").value(false));
        mvc.perform(get("/api/dashboard/business").param("days", "invalid")).andExpect(status().isBadRequest());
        verifyNoInteractions(service);
    }

    @Test void databaseFailuresAreNotReportedAsEmptyDataOrExposedToTheClient() throws Exception {
        when(service.overview(7)).thenThrow(new IllegalStateException("SECRET_DATABASE_DETAILS"));
        mvc.perform(get("/api/dashboard/business")).andExpect(status().isInternalServerError())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.data").doesNotExist())
                .andExpect(content().string(not(containsString("SECRET_DATABASE_DETAILS"))));
    }
}
