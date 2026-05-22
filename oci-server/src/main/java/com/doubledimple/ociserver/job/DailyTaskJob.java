package com.doubledimple.ociserver.job;

import lombok.extern.slf4j.Slf4j;
import org.quartz.Job;
import org.quartz.JobExecutionContext;


@Slf4j
public class DailyTaskJob implements Job {
    @Override
    public void execute(JobExecutionContext context) {}
}
