package com.doubledimple.ociserver;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.regex.Pattern;

import static org.junit.jupiter.api.Assertions.assertTrue;

class PasswordPolicyResourceTest {

    @Test
    void sharedVuePasswordPolicyDefaultsTo120DaysAndAllowsZeroTo365Days() throws IOException {
        String component = readFrontend("views/tenants/components/TenantIdentityDialogs.vue");

        assertTrue(component.contains("expiryDays: 120"));
        assertTrue(Pattern.compile("v-model=\"policyForm.expiryDays\"[^>]*:min=\"0\"[^>]*:max=\"365\"")
                .matcher(component).find());
        assertTrue(component.contains("!Number.isInteger(days) || days < 0 || days > 365"));
    }

    @Test
    void desktopAndMobileUseTheSamePasswordPolicyEditor() throws IOException {
        assertTrue(readFrontend("views/tenants/TenantsView.vue").contains("<TenantIdentityDialogs"));
        assertTrue(readFrontend("views/tenants/MobileTenantToolsView.vue").contains("<TenantIdentityDialogs"));
    }

    @Test
    void passwordPolicyMessagesRemainAvailableInBothVueLanguages() throws IOException {
        String messages = readFrontend("i18n/tenants/identity.ts");
        assertTrue(messages.contains("neverExpires: '永不过期'"));
        assertTrue(messages.contains("neverExpires: 'Never expires'"));
        assertTrue(messages.contains("0 至 365"));
        assertTrue(messages.contains("0 to 365"));
    }

    private String readFrontend(String path) throws IOException {
        return new String(Files.readAllBytes(Paths.get("..", "oci-start-web", "src", path)), StandardCharsets.UTF_8);
    }
}
