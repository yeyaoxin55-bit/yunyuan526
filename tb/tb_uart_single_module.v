`timescale 1ns/1ps

module tb_uart_single_module;
    integer module_count;
    reg [1023:0] token;
    integer fd;
    integer rc;

    initial begin
        module_count = 0;
        fd = $fopen("rtl/uart.v", "r");
        if (fd == 0) begin
            $display("FAIL uart_single_module: cannot open rtl/uart.v");
            $finish;
        end

        while (!$feof(fd)) begin
            rc = $fscanf(fd, "%s", token);
            if (rc == 1 && token == "module") begin
                module_count = module_count + 1;
            end
        end
        $fclose(fd);

        if (module_count !== 1) begin
            $display("FAIL uart_single_module: module_count=%0d", module_count);
            $finish;
        end

        $display("PASS uart_single_module completed");
        $finish;
    end
endmodule
