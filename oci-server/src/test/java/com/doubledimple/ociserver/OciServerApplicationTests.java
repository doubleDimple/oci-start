package com.doubledimple.ociserver;

import cn.hutool.core.util.IdUtil;
import cn.hutool.http.HttpRequest;
import cn.hutool.json.JSONObject;
import cn.hutool.json.JSONUtil;
import com.doubledimple.dao.entity.InstallApp;
import com.doubledimple.dao.entity.RegisterDetail;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.RegisterDetailRepository;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.ocicommon.enums.oci.AccountTypeSubEnum;
import com.doubledimple.ocicommon.enums.oci.PlanTypeSubEnum;
import com.doubledimple.ocicommon.param.InstallAppNotify;
import com.doubledimple.ocicommon.param.OpenInstanceNotify;
import com.doubledimple.ocicommon.param.ScriptResult;
import com.doubledimple.ocicommon.utils.JschUtils;
import com.doubledimple.ocicommon.utils.PingResultParser;
import com.doubledimple.ociserver.pojo.domain.dto.OciClassLoaderPojo;
import com.doubledimple.ociserver.pojo.domain.dto.OracleInstanceDetail;
import com.doubledimple.ociserver.pojo.domain.dto.User;
import com.doubledimple.ociserver.pojo.enums.MessageEnum;
import com.doubledimple.ociserver.third.netdata.NetDataClient;
import com.doubledimple.ociserver.third.netdata.NetDataManager;
import com.doubledimple.ociserver.utils.google.GcpApiUtil;
import com.doubledimple.ociserver.utils.oracle.OciClassLoader;
import com.doubledimple.ociserver.service.message.DingDingMessageService;
import com.doubledimple.ociserver.service.message.factory.MessageFactory;
import com.doubledimple.ociserver.service.oracle.OracleInstanceService;
import com.doubledimple.ociserver.pojo.response.OciIpRange;
import com.doubledimple.ociserver.service.IpQualityCheckService;
import com.doubledimple.ociserver.service.OciIpRangeService;
import com.doubledimple.ociserver.service.OpenApiService;
import com.doubledimple.ociserver.config.task.StartBootInstanceTask;
import com.oracle.bmc.core.model.Instance;
import com.oracle.bmc.ospgateway.model.Subscription;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.web.client.RestTemplate;

import javax.annotation.Resource;
import java.io.IOException;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutionException;

import static com.doubledimple.ocicommon.utils.JschUtils.generatePingScript;

//@SpringBootTest
@Slf4j
public class OciServerApplicationTests {

    @Resource
    OracleInstanceService oracleInstanceService;

    @Resource
    private OciClassLoader ociClassLoader;

    @Resource
    private TenantRepository tenantRepository;

    @Resource
    MessageFactory messageFactory;

    @Resource
    RestTemplate restTemplate;

    @Resource
    RegisterDetailRepository registerDetailRepository;

    private static final String BASE_URL = "https://tools.ipip.net/ping.php";

    @Resource
    StartBootInstanceTask startBootInstanceTask;

    /*@Resource
    RedisUtil redisUtil;*/

    @Resource
    IpQualityCheckService ipQualityCheckService;

    @Resource
    private DingDingMessageService dingDingMessageService;

    //@Test
    public void queryInstances(){
        List<Tenant> all = tenantRepository.findAll();
        for (Tenant tenant : all) {
            User user = new User();
            user.setUserId(tenant.getTenantId());
            user.setTenancy(tenant.getTenancy());
            user.setFingerprint(tenant.getFingerprint());
            user.setKeyFile(tenant.getKeyFile());
            OciClassLoaderPojo pojo = ociClassLoader.loadOci(user);
            List<Instance> allInstances = oracleInstanceService.getAllInstances(pojo.getAuthenticationDetailsProvider());

            System.out.println(allInstances);
        }


    }

    //@Test
    public void testChannel(){
        OracleInstanceDetail instanceData = new OracleInstanceDetail();
        instanceData.setArchitecture("arm");
        instanceData.setRegion("芝加哥");
        instanceData.setUserName("");
        instanceData.setPublicIp("");
        instanceData.setShape("");
        Optional<RegisterDetail> byTenantId = registerDetailRepository.findByTenantId(1+"");

        messageFactory.getType(MessageEnum.TELEGRAM).sendMessage(instanceData);
    }


    //@Test
    public void testPing(){
        // 构建请求参数
        HashMap<String, Object> paramMap = new HashMap<>();
        paramMap.put("v", 4);
        paramMap.put("t", "152.53.1.173");
        paramMap.put("node", "default");

        // 发送请求
        String result = HttpRequest.get(BASE_URL)
                .header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36")
                .header("Accept", "application/json, text/javascript, */*; q=0.01")
                .header("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")
                .header("X-Requested-With", "XMLHttpRequest")
                .header("Referer", "https://tools.ipip.net/ping.php")
                .form(paramMap)  // 设置表单参数
                .execute()
                .body();

        System.out.println(result);

        // 如果需要转换为对象
        JSONObject jsonResult = JSONUtil.parseObj(result);
        System.out.println(jsonResult);
    }


    //@Test
    public void test(){
        final long l = System.currentTimeMillis();
        //redisUtil.zadd(DELAYED_TASKS_KEY,l,"task00000001");
    }


    //@Test
    /*public void testRedis(){
        //redisUtil.set("test","test");
        final long l = System.currentTimeMillis();
        System.out.println(l);
        final Set<String> delayed_tasks = redisUtil.zrangeByScore("delayed_tasks", 0, l);
        System.out.println(delayed_tasks);

    }*/


    //@Test
    public void testSsh(){
        String userName = "root";
        String password = "12345678";
        String host = "localhost";
        List<String> ipAddresses = new ArrayList<>();
        ipAddresses.add("27.106.122.104");
        ipAddresses.add("37.114.54.31");
        ipAddresses.add("373.114.54.31");
        ScriptResult ls = JschUtils.executeScriptJsch(host, userName, password,22, generatePingScript(ipAddresses,4));
        System.out.println(ls.getOutput());
        System.out.println("<===================>");
        List<String> failedIPs = PingResultParser.getFailedIPs(ls.getOutput());
        System.out.println("失败的结果是: " + failedIPs);
    }


    //@Test
    public void  testIpconnect(){
        ipQualityCheckService.checkAllInstancesIpQuality();
    }


    @Resource
    private OciIpRangeService ociIpRangeService;
    //@Test
    public void testCache(){
        final List<OciIpRange> allIpRanges = ociIpRangeService.getAllIpRanges();
        log.info(JSONUtil.toJsonStr(allIpRanges));


        final List<OciIpRange> allIpRanges1 = ociIpRangeService.getAllIpRanges();
        log.info(JSONUtil.toJsonStr(allIpRanges1));
    }


    @Resource
    private OpenApiService openApiService;

    //@Test
    public void testOPenApipenApi(){
        OpenInstanceNotify openInstanceNotify = new OpenInstanceNotify();
        openInstanceNotify.setArchitecture("ARM");
        openInstanceNotify.setRegion("ap-singapore-2");
        //openApiService.notify(openInstanceNotify);

        InstallApp installApp = new InstallApp();
        installApp.setIpAddress("192.168.3.11");
        installApp.setUniqueId(IdUtil.getSnowflakeNextIdStr()+"_"+installApp.getIpAddress());
        installApp.setCreateTime(LocalDateTime.now());
        installApp.setUpdateTime(LocalDateTime.now());
        installApp.setInstallTime(LocalDateTime.now());
        final InstallAppNotify installAppNotify = openApiService.installApp(installApp);
        //log.info(JSONUtil.toJsonStr(installAppNotify));
    }

    private String defaultProjectId = "uplifted-elixir-463402-i6";

    private String credentialsPath = "/Users/admin/Downloads/uplifted-elixir-463402-i6-941962a4b652.json";

    @Resource
    private GcpApiUtil gcpApiUtil;

    //@Test
    public void testGoogle() throws IOException, ExecutionException, InterruptedException {
        //List<ZoneInfo> zoneInfos = gcpApiUtil.listZones(defaultProjectId, credentialsPath);
        //List<GcpRegionZoneEnum.ZoneInfoWithChinese> chineseZones = GcpZoneUtil.convertApiZonesToChineseZones(zoneInfos);
        //System.out.println(JSONUtil.toJsonStr(chineseZones));

        //List<ImageInfo> imageInfos = gcpApiUtil.getLatestDebianAndUbuntuImages(credentialsPath,3);
        //System.out.println(JSONUtil.toJsonStr(imageInfos));


        //FirewallInfo firewallRule = gcpApiUtil.getFirewallRule(defaultProjectId, "allow-ssh", credentialsPath);
        //System.out.println(JSONUtil.toJsonStr(firewallRule));

        //gcpApiUtil.createInstanceRootPassAndFirewall(defaultProjectId,GcpRegionZoneEnum.ASIA_EAST1.getZones().get(0).getZoneName(),"test-instance-3", "e2-standard-2", GcpPublicImageEnum.getDefaultImage(), 20, "12345678@@@", null, credentialsPath );
    }


    @Resource
    NetDataManager netDataManager;

    @Resource
    NetDataClient netDataClient;
    //@Test
    public void installNetData(){
        /*final boolean b =
                netDataManager.installMaster("27.106.122.104","root","2024091987@=@123Xx",22);
        log.info("安装结果: {}",b);*/

        /*String key = "19f3ef5a-75be-43fa-91f7-eabc3b7cfb4f";
        String masterAddress = "47.79.95.189";
        netDataManager.installChildNodeOnVPS(masterAddress,key,"46.232.60.97","root","j)ZBz4+x1AV7m4",22);*/

        final List<String> allHosts = netDataClient.getAllHosts("27.106.122.104", 19999);
        //log.info("所有主机: {}",allHosts);
    }

}
