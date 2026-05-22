package com.doubledimple.ociserver.config;

import org.quartz.Scheduler;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.ApplicationContext;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.quartz.SchedulerFactoryBean;
import org.springframework.scheduling.quartz.SpringBeanJobFactory;

import javax.annotation.Resource;
import javax.sql.DataSource;
import java.util.Properties;

/**
 * Quartz调度器配置
 * 统一管理所有定时任务
 */
@Configuration
public class QuartzConfig {

    @Resource
    private ApplicationContext applicationContext;

    @Resource
    private DataSource dataSource;

    @Value("${spring.datasource.url}")
    private String url;

    @Value("${spring.datasource.username}")
    private String userName;

    @Value("${spring.datasource.password}")
    private String passWd;

    @Value("${spring.datasource.driverClassName}")
    private String driver;

    @Bean
    public SpringBeanJobFactory springBeanJobFactory() {
        SpringBeanJobFactory jobFactory = new SpringBeanJobFactory();
        jobFactory.setApplicationContext(applicationContext);
        return jobFactory;
    }

    /**
     * 配置Quartz调度器
     */
    @Bean
    public SchedulerFactoryBean schedulerFactoryBean() {
        SchedulerFactoryBean schedulerFactoryBean = new SchedulerFactoryBean();
        schedulerFactoryBean.setJobFactory(springBeanJobFactory());

        schedulerFactoryBean.setDataSource(dataSource);
        schedulerFactoryBean.setOverwriteExistingJobs(true);
        schedulerFactoryBean.setAutoStartup(true);
        schedulerFactoryBean.setWaitForJobsToCompleteOnShutdown(true);
        schedulerFactoryBean.setStartupDelay(5);
        schedulerFactoryBean.setApplicationContextSchedulerContextKey("applicationContext");

        Properties quartzProperties = new Properties();
        quartzProperties.put("org.quartz.scheduler.instanceName", "OciServerScheduler");
        quartzProperties.put("org.quartz.scheduler.instanceId", "AUTO");

        // 线程池配置
        quartzProperties.put("org.quartz.threadPool.class", "org.quartz.simpl.SimpleThreadPool");
        quartzProperties.put("org.quartz.threadPool.threadCount", "20");
        quartzProperties.put("org.quartz.threadPool.threadPriority", "5");

        // 持久化配置
        quartzProperties.put("org.quartz.jobStore.class", "org.quartz.impl.jdbcjobstore.JobStoreTX");
        quartzProperties.put("org.quartz.jobStore.driverDelegateClass", "org.quartz.impl.jdbcjobstore.StdJDBCDelegate");
        quartzProperties.put("org.quartz.jobStore.tablePrefix", "QRTZ_");
        quartzProperties.put("org.quartz.jobStore.useProperties", "true");
        quartzProperties.put("org.quartz.jobStore.isClustered", "false");
        quartzProperties.put("org.quartz.jobStore.misfireThreshold", "60000");

        // ➡️ 添加 DataSource 配置，引用 Spring DataSource
        quartzProperties.put("org.quartz.jobStore.dataSource", "myDS");
        quartzProperties.put("org.quartz.dataSource.myDS.provider", "hikaricp");
        quartzProperties.put("org.quartz.dataSource.myDS.driver", driver);
        quartzProperties.put("org.quartz.dataSource.myDS.URL", url);
        quartzProperties.put("org.quartz.dataSource.myDS.user", userName);
        quartzProperties.put("org.quartz.dataSource.myDS.password", passWd);
        quartzProperties.put("org.quartz.dataSource.myDS.maxConnections", "5");

        schedulerFactoryBean.setQuartzProperties(quartzProperties);

        return schedulerFactoryBean;
    }

    /**
     * 显式创建Scheduler Bean
     */
    @Bean
    public Scheduler scheduler(SchedulerFactoryBean schedulerFactoryBean) {
        schedulerFactoryBean.setAutoStartup(false);
        return schedulerFactoryBean.getScheduler();
    }
}
