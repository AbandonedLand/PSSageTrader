write-spectrehost "
    [teal]
    The grid bot works like a ladder. Every step on the ladder is a price point where you will offer a bid/ask spread.
    The bot will calculate how much to offer of each token type.  [/]
    
    
    Example:
    
    MAX XCH Exposure:       [green]10 XCH[/]
    MAX wUSDC.b Exposure:   [blue]100 wUSDC.b[/]
    Min Price:              [lightcoral]9.00[/]         [gray]NOTE: The price is always token_y / token_x.[/]
    Current Price:          [darkorange3]10.00[/]        [gray]NOTE: If XCH is involved, it will always be token_x.[/]
    Max Price:              [maroon]11.00[/]
    Steps:                  [cyan1]25[/]           [gray]NOTE: The steps are each side of the Current Price.[/]
    
    Fee:                    [darkseagreen1]0.3%[/]         [gray]NOTE: This fee is applied to each side of the spread.[/]
    Fee_Paid_in:            [green]XCH[/]          [gray]NOTE: The fee is paid in XCH.[/]    
    
    XCH Per Step:           [purple4_1]0.4 XCH[/]      [gray]NOTE: 10/ 25 = 0.4 XCH per step.[/]
    XCH Fee Per Step:       [darkseagreen1]0.0006 XCH[/]   [gray]NOTE: 0.15% of 0.4 XCH = 0.0006 XCH.[/]
    
    [gray]
    Step 0:
        - Price: [darkorange3]10.00[/]
        - Bid:   [gray]Buying wUSDC.b from XCH at 10.00[/]
            - Offered: 
                - XCH:      [purple4_1]  400000000000[/]
                - Fee:      [darkseagreen1]-    600000000[/]
                - Total:    [purple4_1]  399400000000[/]
            - Requested:
                - wUSDC.b:    [blue]  4000[/]
            - Actual Price: [darkorange3]10.015[/]
        - Ask:  [gray]Selling wUSDC.b for XCH at 10.00[/]
            - Offered:
                - wUSDC.b:    [blue]  4000[/]
            - Requested:
                - XCH:      [purple4_1]  400000000000[/]
                - Fee:      [darkseagreen1]+    600000000[/]
                - Total:    [purple4_1]  400600000000[/]
            - Actual Price: [darkorange3]9.985[/]

            
        
    [/]"