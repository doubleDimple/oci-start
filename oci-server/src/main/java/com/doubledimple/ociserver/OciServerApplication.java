package com.doubledimple.ociserver;

import com.doubledimple.ociserver.config.OracleUsersConfig;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;
import org.springframework.boot.context.properties.EnableConfigurationProperties;


@SpringBootApplication
@EnableConfigurationProperties(OracleUsersConfig.class)
public class OciServerApplication {

    public static void main(String[] args) {
        SpringApplication.run(OciServerApplication.class, args);
    }

}
