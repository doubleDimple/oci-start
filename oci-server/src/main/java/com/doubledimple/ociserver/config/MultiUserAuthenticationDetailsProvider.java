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
import java.nio.file.Path;
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

    /**
     * Security: restrict where OCI API private key files may be read from.
     * Put private keys under this directory and lock down permissions (dir 700, file 600).
     */
    private static final Path KEYFILE_BASEDIR = Path.of("/opt/oci-keys").toAbsolutePath().normalize();

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

            // Validate keyFile path (must be under KEYFILE_BASEDIR)
            Path keyPath = Paths.get(user.getKeyFile()).toAbsolutePath().normalize();
            if (!keyPath.startsWith(KEYFILE_BASEDIR)) {
                log.error("Skip user {}: keyFile path is not allowed: {} (allowed base dir: {})",
                        user.getUserId(), keyPath, KEYFILE_BASEDIR);
                continue;
            }
            if (!Files.exists(keyPath)) {
                log.error("Skip user {}: keyFile does not exist: {}", user.getUserId(), keyPath);
                continue;
            }
            if (!Files.isRegularFile(keyPath)) {
                log.error("Skip user {}: keyFile is not a regular file: {}", user.getUserId(), keyPath);
                continue;
            }

            SimpleAuthenticationDetailsProvider build = SimpleAuthenticationDetailsProvider.builder().
                    userId(user.getUserId()).
                    fingerprint(user.getFingerprint()).
                    tenantId(user.getTenancy()).
                    privateKeySupplier(() -> {
                        try {
                            return new FileInputStream(keyPath.toFile()); // keyFile path validated above
                        } catch (FileNotFoundException e) {
                            log.error("keyFile not found for user {}: {}", user.getUserId(), keyPath, e);
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
