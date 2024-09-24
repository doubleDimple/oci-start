package com.doubledimple.ociserver;

import com.doubledimple.ociserver.config.MultiUserAuthenticationDetailsProvider;
import com.oracle.bmc.auth.AuthenticationDetailsProvider;
import com.oracle.bmc.auth.ConfigFileAuthenticationDetailsProvider;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.core.ComputeClient;
import com.oracle.bmc.core.VirtualNetworkClient;
import com.oracle.bmc.core.model.Image;
import com.oracle.bmc.core.requests.ListImagesRequest;
import com.oracle.bmc.core.responses.ListImagesResponse;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import java.security.KeyPair;
import java.util.ArrayList;
import java.util.Base64;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;

@SpringBootTest
class OciServerApplicationTests {

    @Autowired
    private MultiUserAuthenticationDetailsProvider multiUserAuthenticationDetailsProvider;

    @Test
    void queryImages() {
        try {
            // 创建身份验证提供者
            Map<String, SimpleAuthenticationDetailsProvider> stringSimpleAuthenticationDetailsProviderMap = multiUserAuthenticationDetailsProvider.simpleAuthenticationDetailsProvider();

            for (SimpleAuthenticationDetailsProvider provider : stringSimpleAuthenticationDetailsProviderMap.values()) {
                // 创建 ComputeClient
                ComputeClient computeClient = new ComputeClient(provider);

                // 查询镜像
                ListImagesRequest request = ListImagesRequest.builder()
                        .compartmentId(provider.getTenantId()) // 替换为你的 compartment ID
                        .build();

                ListImagesResponse response = computeClient.listImages(request);

                // 打印所有可用镜像
                for (Image image : response.getItems()) {
                    System.out.println("镜像名称: " + image.getDisplayName());
                    System.out.println("操作系统: " + image.getOperatingSystem());
                    System.out.println("操作系统版本: " + image.getOperatingSystemVersion());
                    System.out.println("------------");
                }

                // 关闭客户端
                computeClient.close();
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

    }


}
