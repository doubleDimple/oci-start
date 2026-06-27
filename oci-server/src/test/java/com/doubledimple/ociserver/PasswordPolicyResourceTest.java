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
    void desktopPasswordPolicyAllowsZeroTo365DaysAndShowsNeverExpireHint() throws IOException {
        String template = read("src/main/resources/templates/tenant_list.ftl");
        String script = read("src/main/resources/static/js/system/tenant_list.js");

        assertTrue(Pattern.compile("id=\"tenantPasswordExpiryDays\"[\\s\\S]*min=\"0\"[\\s\\S]*max=\"365\"[\\s\\S]*value=\"120\"")
                .matcher(template)
                .find());
        assertTrue(template.contains("${msg.get(\"tenant.passDes5\")}"));
        assertTrue(script.contains("return p.expiryDays == null ? 120 : p.expiryDays;"));
    }

    @Test
    void mobilePasswordPolicyDefaultsTo120DaysAndAllowsZeroTo365Days() throws IOException {
        String template = read("src/main/resources/templates/mobile/user_mgr.ftl");

        assertTrue(Pattern.compile("id=\"policyDays\"[\\s\\S]*min=\"0\"[\\s\\S]*max=\"365\"[\\s\\S]*value=\"120\"")
                .matcher(template)
                .find());
    }

    @Test
    void passwordPolicyMessagesDescribeZeroAsNeverExpiring() throws IOException {
        assertPasswordPolicyMessages(read("src/main/resources/i18n/messages_zh_CN.properties"),
                "tenant.passExoDay=\\u8BBE\\u7F6E\\u5BC6\\u7801\\u8FC7\\u671F\\u5929\\u6570",
                "tenant.passDes5=\\u5F53\\u8FC7\\u671F\\u5929\\u6570\\u8BBE\\u7F6E\\u4E3A0\\u65F6\\uFF0C\\u4EE3\\u8868\\u5BC6\\u7801\\u6C38\\u4E0D\\u8FC7\\u671F");
        assertPasswordPolicyMessages(read("src/main/resources/i18n/messages_zh_TW.properties"),
                "tenant.passExoDay=\\u8A2D\\u7F6E\\u5BC6\\u78BC\\u904E\\u671F\\u5929\\u6578",
                "tenant.passDes5=\\u7576\\u904E\\u671F\\u5929\\u6578\\u8A2D\\u7F6E\\u70BA0\\u6642\\uFF0C\\u4EE3\\u8868\\u5BC6\\u78BC\\u6C38\\u4E0D\\u904E\\u671F");
        assertPasswordPolicyMessages(read("src/main/resources/i18n/messages.properties"),
                "tenant.passExoDay=Set Password Expiration Days",
                "tenant.passDes5=When expiration days is set to 0, the password never expires");
    }

    private void assertPasswordPolicyMessages(String messages, String label, String zeroDaysHint) {
        assertTrue(messages.contains(label));
        assertTrue(messages.contains("0-365"));
        assertTrue(messages.contains("120"));
        assertTrue(messages.contains(zeroDaysHint));
    }

    private String read(String path) throws IOException {
        return new String(Files.readAllBytes(Paths.get(path)), StandardCharsets.UTF_8);
    }
}
