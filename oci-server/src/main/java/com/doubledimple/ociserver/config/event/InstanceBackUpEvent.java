package com.doubledimple.ociserver.config.event;

import com.doubledimple.ociserver.pojo.domain.dto.OracleInstanceDetail;
import org.springframework.context.ApplicationEvent;

import java.time.Clock;

/**
 * @version 1.0.0
 * @ClassName InstanceBackUpEvent
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-05-13 21:37
 */
public class InstanceBackUpEvent extends ApplicationEvent {
    OracleInstanceDetail instanceData;

    public InstanceBackUpEvent(Object source, OracleInstanceDetail instanceData) {
        super(source);
        this.instanceData = instanceData;
    }

    public InstanceBackUpEvent(Object source, Clock clock) {
        super(source, clock);
    }

    public OracleInstanceDetail getInstanceData() {
        return instanceData;
    }
}
