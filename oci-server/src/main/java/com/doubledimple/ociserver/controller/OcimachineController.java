package com.doubledimple.ociserver.controller;

import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.RequestMapping;

/**
 * @author doubleDimple
 * @date 2024:11:03日 20:50
 */
@Controller
@RequestMapping("/oci")
public class OcimachineController  extends BaseController{


    /*@GetMapping("/list")
    public String listUsers(@RequestParam(defaultValue = "0") int page,
                            @RequestParam(defaultValue = "5") int size,
                            Model model) {
        Page<Tenant> userPage = tenantService.getAllTenants(page, size);
        model.addAttribute("tenants", userPage.getContent());
        model.addAttribute("currentPage", page);
        model.addAttribute("totalPages", userPage.getTotalPages());
        return "oci_machine_list";
    }*/
}
