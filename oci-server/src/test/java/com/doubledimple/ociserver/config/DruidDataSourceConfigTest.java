package com.doubledimple.ociserver.config;

import com.alibaba.druid.pool.DruidDataSource;
import com.alibaba.druid.spring.boot.autoconfigure.DruidDataSourceAutoConfigure;
import org.junit.jupiter.api.Test;
import org.quartz.Scheduler;
import org.springframework.boot.autoconfigure.AutoConfigurations;
import org.springframework.boot.autoconfigure.jdbc.DataSourceAutoConfiguration;
import org.springframework.boot.autoconfigure.jdbc.DataSourceTransactionManagerAutoConfiguration;
import org.springframework.boot.autoconfigure.quartz.QuartzAutoConfiguration;
import org.springframework.boot.test.context.ConfigDataApplicationContextInitializer;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.scheduling.quartz.LocalDataSourceJobStore;
import org.springframework.scheduling.quartz.SchedulerFactoryBean;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assertions.assertThrows;

class DruidDataSourceConfigTest {

    @Test
    void hikariCpIsExcludedFromClasspath() {
        assertThrows(ClassNotFoundException.class, () -> Class.forName("com.zaxxer.hikari.HikariDataSource"));
    }

    @Test
    void loadsApplicationYmlWithDruidPoolAndDisablesStatEndpoints() {
        String dbName = "druid_cfg_" + UUID.randomUUID().toString().replace("-", "");
        new ApplicationContextRunner()
                .withInitializer(new ConfigDataApplicationContextInitializer())
                .withConfiguration(AutoConfigurations.of(
                        DruidDataSourceAutoConfigure.class,
                        DataSourceAutoConfiguration.class
                ))
                .withPropertyValues(
                        "spring.datasource.url=jdbc:h2:mem:" + dbName + ";DB_CLOSE_DELAY=-1"
                )
                .run(context -> {
                    assertThat(context).hasNotFailed();
                    assertThat(context).hasSingleBean(DataSource.class);

                    DataSource dataSource = context.getBean(DataSource.class);
                    assertThat(dataSource).isInstanceOf(DruidDataSource.class);

                    DruidDataSource druid = (DruidDataSource) dataSource;
                    assertThat(druid.getInitialSize()).isEqualTo(5);
                    assertThat(druid.getMinIdle()).isEqualTo(5);
                    assertThat(druid.getMaxActive()).isEqualTo(20);
                    assertThat(druid.getValidationQuery()).isEqualTo("SELECT 1");
                    assertThat(druid.isTestWhileIdle()).isTrue();
                    assertThat(druid.isPoolPreparedStatements()).isTrue();
                    assertThat(druid.getProxyFilters()).isNotEmpty();

                    assertThat(context.containsBean("statViewServletRegistrationBean")).isFalse();
                    assertThat(context.containsBean("webStatFilterRegistrationBean")).isFalse();

                    try (Connection conn = druid.getConnection();
                         Statement stmt = conn.createStatement();
                         ResultSet rs = stmt.executeQuery("SELECT 1")) {
                        assertThat(rs.next()).isTrue();
                        assertThat(rs.getInt(1)).isEqualTo(1);
                    }
                });
    }

    @Test
    void quartzReusesPrimaryDruidDataSourceWithLocalDataSourceJobStore() {
        String dbName = "druid_quartz_" + UUID.randomUUID().toString().replace("-", "");
        new ApplicationContextRunner()
                .withInitializer(new ConfigDataApplicationContextInitializer())
                .withConfiguration(AutoConfigurations.of(
                        DruidDataSourceAutoConfigure.class,
                        DataSourceAutoConfiguration.class,
                        DataSourceTransactionManagerAutoConfiguration.class,
                        QuartzAutoConfiguration.class
                ))
                .withUserConfiguration(QuartzConfig.class)
                .withPropertyValues(
                        "spring.datasource.url=jdbc:h2:mem:" + dbName + ";DB_CLOSE_ON_EXIT=FALSE;DB_CLOSE_DELAY=-1"
                )
                .run(context -> {
                    assertThat(context).hasNotFailed();
                    assertThat(context.getBean(DataSource.class)).isInstanceOf(DruidDataSource.class);

                    SchedulerFactoryBean factoryBean = context.getBean(SchedulerFactoryBean.class);
                    assertThat(factoryBean).isNotNull();

                    Scheduler scheduler = context.getBean("scheduler", Scheduler.class);
                    assertThat(scheduler.getMetaData().getJobStoreClass())
                            .isEqualTo(LocalDataSourceJobStore.class);
                });
    }
}
