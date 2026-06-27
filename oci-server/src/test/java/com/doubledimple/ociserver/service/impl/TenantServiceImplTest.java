package com.doubledimple.ociserver.service.impl;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertThrows;

class TenantServiceImplTest {

    @Test
    void rejectsPasswordExpiryDaysBelowZero() {
        TenantServiceImpl service = new TenantServiceImpl();

        assertThrows(IllegalArgumentException.class,
                () -> service.updateUserPasswordPolicy("1", true, -1));
    }

    @Test
    void rejectsPasswordExpiryDaysAbove365() {
        TenantServiceImpl service = new TenantServiceImpl();

        assertThrows(IllegalArgumentException.class,
                () -> service.updateUserPasswordPolicy("1", true, 366));
    }
}
