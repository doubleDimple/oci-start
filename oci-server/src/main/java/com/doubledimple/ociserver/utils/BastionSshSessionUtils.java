package com.doubledimple.ociserver.utils;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ocicommon.enums.RegionEnum;
import com.doubledimple.ociserver.utils.oracle.OciUtils;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.bastion.BastionClient;
import com.oracle.bmc.bastion.model.CreatePortForwardingSessionTargetResourceDetails;
import com.oracle.bmc.bastion.model.CreateSessionDetails;
import com.oracle.bmc.bastion.requests.CreateSessionRequest;
import com.oracle.bmc.bastion.responses.CreateSessionResponse;

/**
 * @version 1.0.0
 * @ClassName BastionSshSessionUtils
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-04-06 15:17
 */
public class BastionSshSessionUtils {



    public void executeCommand(Tenant tenant){
        final SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
        BastionClient bastionClient = BastionClient.builder().build(provider);
        bastionClient.setRegion(RegionEnum.getRegionCode(tenant.getRegion()));


        CreatePortForwardingSessionTargetResourceDetails targetResourceDetails =
                CreatePortForwardingSessionTargetResourceDetails.builder()
                        .targetResourceId("ocid1.instance.oc1..xxxxx")
                        .targetResourcePrivateIpAddress("10.0.0.23")
                        .targetResourcePort(22)
                        .build();

        CreateSessionDetails build = CreateSessionDetails.builder().targetResourceDetails(targetResourceDetails)
                .bastionId("ocid1.bastion.oc1.xxxx")
                .build();
        CreateSessionRequest request = CreateSessionRequest.builder()
                .createSessionDetails(build)
                .build();


        CreateSessionResponse response = bastionClient.createSession(request);
        System.out.println("Session ID: " + response.getSession().getId());

        String sessionLifecycleState = response.getSession().getLifecycleState().getValue();





    }
}
