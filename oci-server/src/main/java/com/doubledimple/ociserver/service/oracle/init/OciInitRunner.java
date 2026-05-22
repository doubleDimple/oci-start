package com.doubledimple.ociserver.service.oracle.init;

import com.oracle.bmc.Realm;
import com.oracle.bmc.Region;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;

import static com.oracle.bmc.Region.register;


/**
 * @version 1.0.0
 * @ClassName OciInitRunner
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-05-24 10:07
 */
@Component
@Slf4j
public class OciInitRunner implements ApplicationRunner {

    private static String region_name = "ap-kulai-2";
    private static String region_key = "JBP";
    @Override
    public void run(ApplicationArguments args) throws Exception {
        try {
            //Region.fromRegionId(region_name);
        } catch (Exception e) {
            //register(region_name, Realm.OC1, region_key);
            log.info("oci-start start register new region:{} success", region_name);
        }
    }
}
