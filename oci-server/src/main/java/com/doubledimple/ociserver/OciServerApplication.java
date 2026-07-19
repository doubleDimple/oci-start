package com.doubledimple.ociserver;

import com.doubledimple.ociserver.pojo.enums.MessageEnum;
import com.doubledimple.ociserver.service.message.factory.MessageFactory;
import com.oracle.bmc.Realm;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.BeansException;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.domain.EntityScan;
import org.springframework.boot.autoconfigure.security.servlet.SecurityAutoConfiguration;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.ApplicationContext;
import org.springframework.context.ApplicationContextAware;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.context.annotation.ComponentScan;
import org.springframework.core.env.Environment;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;
import org.springframework.retry.annotation.EnableRetry;
import org.springframework.scheduling.annotation.EnableAsync;
import org.springframework.scheduling.annotation.EnableScheduling;

import javax.annotation.Resource;

import java.net.InetAddress;
import java.net.UnknownHostException;

import static com.doubledimple.ocicommon.utils.IpUtils.getPublicIp2;
import static com.oracle.bmc.Region.register;

@SpringBootApplication(exclude = {SecurityAutoConfiguration.class})
@EnableScheduling
@EnableAsync
@Slf4j
@ComponentScan(basePackages = {
        "com.doubledimple.ociserver",
        "com.doubledimple.dao",
        "com.doubledimple.ociai",
        "com.doubledimple.ocimonitor"
})
@EnableJpaRepositories(basePackages = {
        "com.doubledimple.dao.repository"
})
@EntityScan(basePackages = {
        "com.doubledimple.dao.entity"
})
@EnableRetry
public class OciServerApplication{

    public static void main(String[] args) {
        long startTime = System.currentTimeMillis();
        ConfigurableApplicationContext context = SpringApplication.run(OciServerApplication.class, args);
        // 静态工具取 Bean 依赖此上下文（TenantProxyBinder / OciUtils.getProvider）
        com.doubledimple.ociserver.config.SpringAppContext.set(context);
        Environment env = context.getEnvironment();

        String protocol = "http";
        if (env.getProperty("server.ssl.key-store") != null) protocol = "https";
        String serverPort = env.getProperty("server.port", "9856");
        String contextPath = env.getProperty("server.servlet.context-path", "");

        // --- 修改开始：获取 IP 逻辑 ---
        String localIp = "localhost";
        String publicIp = "Unknown";

        try {
            localIp = InetAddress.getLocalHost().getHostAddress();
            publicIp = getPublicIp2();

        } catch (Exception e) {
            log.warn("IP获取失败: {}", e.getMessage());
        }

        double duration = (System.currentTimeMillis() - startTime) / 1000.0;

        log.info("\n----------------------------------------------------------\n\t" +
                        "Application '{}' is running successfully!\n\t" +
                        "ID: \t\t\t{}\n\t" +
                        "Local Access: \t{}://localhost:{}{}\n\t" +
                        "LAN Access: \t{}://{}:{}{}\n\t" +
                        "Public Access: \t{}://{}:{}{}  <-- (公网访问地址)\n\t" +
                        "Profile(s): \t{}\n\t" +
                        "Startup Time: \t{} seconds\n" +
                        "----------------------------------------------------------",
                env.getProperty("spring.application.name", "OCI-Server"),
                context.getId(),
                protocol, serverPort, contextPath,
                protocol, localIp, serverPort, contextPath,
                protocol, publicIp, serverPort, contextPath,
                env.getActiveProfiles(),
                String.format("%.2f", duration));
    }
}
