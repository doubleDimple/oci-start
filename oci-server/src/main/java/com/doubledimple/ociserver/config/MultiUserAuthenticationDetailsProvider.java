package com.doubledimple.ociserver.config;

import com.doubledimple.ociserver.domain.User;
import com.oracle.bmc.ConfigFileReader;
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.*;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.DependsOn;
import org.springframework.stereotype.Component;
import org.springframework.stereotype.Service;

import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.HashMap;
import java.util.Map;

/**
 * @author doubleDimple
 * @date 2024:09:22日 12:27
 */
@Component
@Slf4j
public class MultiUserAuthenticationDetailsProvider {

    private final OracleUsersConfig oracleUserConfig;

    @Autowired
    public MultiUserAuthenticationDetailsProvider(@Qualifier("oracleUsersConfig")OracleUsersConfig oracleUserConfig) {
        this.oracleUserConfig = oracleUserConfig;
    }

    @Bean("simpleAuthenticationDetailsProvider")
    public Map<String, SimpleAuthenticationDetailsProvider> simpleAuthenticationDetailsProvider() throws IOException {
        Map<String, SimpleAuthenticationDetailsProvider> providers = new HashMap<>();
        for (Map.Entry<String, User> entry : oracleUserConfig.getUsers().entrySet()) {
            String userName = entry.getValue().getUserId();
            User user = entry.getValue();

            SimpleAuthenticationDetailsProvider build = SimpleAuthenticationDetailsProvider.builder().
                    userId(user.getUserId()).
                    fingerprint(user.getFingerprint()).
                    tenantId(user.getTenancy()).
                    privateKeySupplier(() -> {
                        try {
                            return new FileInputStream(user.getKeyFile()); // 密钥文件路径
                        } catch (FileNotFoundException e) {
                            e.printStackTrace();
                            return null;
                        }
                    }).
                    region(Region.fromRegionId(user.getRegion()))
                    .build();

            providers.put(userName,build);
        }

        return providers;
    }

}
