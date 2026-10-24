package com.doubledimple.ociserver.config;

import com.doubledimple.ociserver.controller.login.PasswordResetController;
import com.doubledimple.ociserver.service.VerifyService;
import org.junit.jupiter.api.Test;
import org.springframework.context.annotation.ClassPathScanningCandidateComponentProvider;
import org.springframework.core.type.filter.AnnotationTypeFilter;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.request;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class PasswordRecoveryDisabledTest {

    @Test
    void passwordRecoveryIsNotDiscoveredAsASpringComponent() {
        ClassPathScanningCandidateComponentProvider scanner = new ClassPathScanningCandidateComponentProvider(false);
        scanner.addIncludeFilter(new AnnotationTypeFilter(Component.class));
        assertFalse(scanner.findCandidateComponents("com.doubledimple.ociserver.controller.login").stream()
                .anyMatch(bean -> PasswordResetController.class.getName().equals(bean.getBeanClassName())));
    }

    @Test
    void recoveryEndpointsCannotBeCalledEvenWhenTheOldControllerIsExplicitlySupplied() throws Exception {
        VerifyService service = mock(VerifyService.class);
        PasswordResetController controller = new PasswordResetController();
        ReflectionTestUtils.setField(controller, "verifyService", service);
        MockMvc mvc = MockMvcBuilders.standaloneSetup(controller).build();

        for (String path : new String[]{"/api/send-reset-code", "/api/verify-reset-code", "/api/reset-password"}) {
            for (HttpMethod method : new HttpMethod[]{HttpMethod.GET, HttpMethod.POST}) {
                mvc.perform(request(method, path)
                        .contentType(MediaType.APPLICATION_JSON)
                        .header("Reset-Token", "old-reset-token")
                        .content("{\"username\":\"account\",\"verificationCode\":\"123456\",\"resetToken\":\"old-reset-token\"}"))
                        .andExpect(status().isNotFound());
            }
        }
        verifyNoInteractions(service);
    }
}
