local HoneycombCMD = {}

-- Configuration (User can modify these)
local PREFIX = "-"  -- Change this to customize command prefix

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")

local LocalPlayer = Players.LocalPlayer

-- Internal Configuration
local Config = {
    Theme = {
        Primary = Color3.fromRGB(20, 20, 20),      -- Dark background
        Secondary = Color3.fromRGB(40, 40, 40),    -- Lighter background
        Accent = Color3.fromRGB(220, 50, 50),      -- Red accent
        AccentDark = Color3.fromRGB(180, 40, 40),  -- Darker red
        Text = Color3.fromRGB(255, 255, 255),      -- White text
        TextDim = Color3.fromRGB(180, 180, 180),   -- Gray text
        Success = Color3.fromRGB(50, 220, 50),     -- Green
        Warning = Color3.fromRGB(220, 220, 50),    -- Yellow
        Error = Color3.fromRGB(220, 50, 50),       -- Red
    },
    MaxHistory = 50,
    AutoCompleteLimit = 10,
    MobileButtonSize = 60,
}

-- Internal state
local commands = {}
local commandHistory = {}
local chatConnection = nil
local cmdBarGui = nil
local mobileGui = nil
local isCommandBarOpen = false
local currentSuggestionIndex = 0
local suggestions = {}
local playersList = {}

-- Update players list
local function UpdatePlayersList()
    playersList = {}
    for _, player in pairs(Players:GetPlayers()) do
        table.insert(playersList, {
            name = player.Name,
            displayName = player.DisplayName,
            player = player
        })
    end
end

-- Initialize players list and keep it updated
UpdatePlayersList()
Players.PlayerAdded:Connect(UpdatePlayersList)
Players.PlayerRemoving:Connect(UpdatePlayersList)

-- Utility functions
local function CreateCorner(radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    return corner
end

local function CreateStroke(color, thickness)
    local stroke = Instance.new("UIStroke")
    stroke.Color = color or Config.Theme.Accent
    stroke.Thickness = thickness or 1
    return stroke
end

local function CreatePadding(padding)
    local pad = Instance.new("UIPadding")
    if typeof(padding) == "number" then
        pad.PaddingTop = UDim.new(0, padding)
        pad.PaddingBottom = UDim.new(0, padding)
        pad.PaddingLeft = UDim.new(0, padding)
        pad.PaddingRight = UDim.new(0, padding)
    else
        pad.PaddingTop = UDim.new(0, padding.Top or 0)
        pad.PaddingBottom = UDim.new(0, padding.Bottom or 0)
        pad.PaddingLeft = UDim.new(0, padding.Left or 0)
        pad.PaddingRight = UDim.new(0, padding.Right or 0)
    end
    return pad
end

local function CreateLayout(direction, padding)
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = direction or Enum.FillDirection.Vertical
    layout.Padding = UDim.new(0, padding or 5)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    return layout
end

-- Mobile-optimized notification system
local function ShowNotification(text, type, duration)
    local notifGui = Instance.new("ScreenGui")
    notifGui.Name = "HoneycombNotification"
    notifGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    notifGui.DisplayOrder = 999
    notifGui.IgnoreGuiInset = true
    
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 350, 0, 80)
    frame.Position = UDim2.new(1, 20, 0, 40)
    frame.BackgroundColor3 = Config.Theme.Secondary
    frame.Parent = notifGui
    CreateCorner(12).Parent = frame
    CreateStroke(type == "error" and Config.Theme.Error or 
                 type == "success" and Config.Theme.Success or 
                 type == "warning" and Config.Theme.Warning or 
                 Config.Theme.Accent, 3).Parent = frame
    
    local textLabel = Instance.new("TextLabel")
    textLabel.Size = UDim2.new(1, -20, 1, 0)
    textLabel.Position = UDim2.new(0, 10, 0, 0)
    textLabel.BackgroundTransparency = 1
    textLabel.Text = text
    textLabel.TextColor3 = Config.Theme.Text
    textLabel.Font = Enum.Font.GothamMedium
    textLabel.TextSize = 16
    textLabel.TextWrapped = true
    textLabel.TextXAlignment = Enum.TextXAlignment.Left
    textLabel.Parent = frame
    
    -- Animate in
    local tweenIn = TweenService:Create(frame, 
        TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {Position = UDim2.new(1, -370, 0, 40)}
    )
    tweenIn:Play()
    
    -- Auto remove
    task.spawn(function()
        task.wait(duration or 4)
        local tweenOut = TweenService:Create(frame,
            TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            {Position = UDim2.new(1, 20, 0, 40)}
        )
        tweenOut:Play()
        tweenOut.Completed:Connect(function()
            notifGui:Destroy()
        end)
    end)
end

-- Enhanced player finding with display name support
local function FindPlayer(name)
    local nameLower = name:lower()
    
    -- Exact match first (name or display name)
    for _, playerData in pairs(playersList) do
        if playerData.name:lower() == nameLower or playerData.displayName:lower() == nameLower then
            return playerData.player
        end
    end
    
    -- Partial match (name or display name)
    for _, playerData in pairs(playersList) do
        if playerData.name:lower():find(nameLower, 1, true) or 
           playerData.displayName:lower():find(nameLower, 1, true) then
            return playerData.player
        end
    end
    
    return nil
end

-- Argument parsing utilities
local function ParseArguments(argString, expectedArgs)
    local args = {}
    local current = ""
    local inQuotes = false
    local quoteChar = nil
    
    for i = 1, #argString do
        local char = argString:sub(i, i)
        
        if (char == '"' or char == "'") and not inQuotes then
            inQuotes = true
            quoteChar = char
        elseif char == quoteChar and inQuotes then
            inQuotes = false
            quoteChar = nil
        elseif char == " " and not inQuotes then
            if current ~= "" then
                table.insert(args, current)
                current = ""
            end
        else
            current = current .. char
        end
    end
    
    if current ~= "" then
        table.insert(args, current)
    end
    
    -- Type conversion based on expected args
    for i, arg in ipairs(args) do
        if expectedArgs and expectedArgs[i] then
            local expectedType = expectedArgs[i].type
            if expectedType == "number" then
                local num = tonumber(arg)
                if num then
                    args[i] = num
                else
                    return nil, "Argument " .. i .. " must be a number"
                end
            elseif expectedType == "player" then
                local player = FindPlayer(arg)
                if player then
                    args[i] = player
                else
                    return nil, "Player '" .. arg .. "' not found"
                end
            elseif expectedType == "boolean" then
                local lower = arg:lower()
                if lower == "true" or lower == "1" or lower == "yes" then
                    args[i] = true
                elseif lower == "false" or lower == "0" or lower == "no" then
                    args[i] = false
                else
                    return nil, "Argument " .. i .. " must be true/false"
                end
            end
        end
    end
    
    return args
end

-- Command execution
local function ExecuteCommand(commandLine)
    local parts = commandLine:split(" ")
    local cmdName = parts[1]:lower()
    local argString = commandLine:sub(#parts[1] + 2)
    
    if commands[cmdName] then
        local cmd = commands[cmdName]
        local args, error = ParseArguments(argString, cmd.args)
        
        if error then
            ShowNotification("Error: " .. error, "error")
            return false
        end
        
        -- Check required arguments
        if cmd.args then
            for i, argDef in ipairs(cmd.args) do
                if argDef.required and not args[i] then
                    ShowNotification("Error: Missing required argument: " .. argDef.name, "error")
                    return false
                end
            end
        end
        
        -- Add to history
        table.insert(commandHistory, 1, commandLine)
        if #commandHistory > Config.MaxHistory then
            table.remove(commandHistory, #commandHistory)
        end
        
        -- Execute command
        pcall(function()
            cmd.callback(args or {})
        end)
        
        return true
    else
        ShowNotification("Unknown command: " .. cmdName .. ". Type " .. PREFIX .. "help for available commands.", "error")
        return false
    end
end

-- Auto-complete system
local function GetCommandSuggestions(input)
    local suggestions = {}
    local inputLower = input:lower()
    
    for cmdName, cmd in pairs(commands) do
        if cmdName:find(inputLower, 1, true) then
            table.insert(suggestions, {
                name = cmdName,
                description = cmd.description or "No description",
                usage = cmd.usage or (PREFIX .. cmdName)
            })
        end
    end
    
    -- Sort by relevance
    table.sort(suggestions, function(a, b)
        local aStarts = a.name:lower():sub(1, #inputLower) == inputLower
        local bStarts = b.name:lower():sub(1, #inputLower) == inputLower
        
        if aStarts and not bStarts then return true end
        if bStarts and not aStarts then return false end
        
        return a.name < b.name
    end)
    
    -- Limit results
    local limited = {}
    for i = 1, math.min(#suggestions, Config.AutoCompleteLimit) do
        table.insert(limited, suggestions[i])
    end
    
    return limited
end

-- Create mobile command button
local function CreateMobileButton()
    if mobileGui then return end
    
    mobileGui = Instance.new("ScreenGui")
    mobileGui.Name = "HoneycombCMDMobile"
    mobileGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    mobileGui.DisplayOrder = 90
    mobileGui.ResetOnSpawn = false
    mobileGui.IgnoreGuiInset = true
    
    local button = Instance.new("TextButton")
    button.Name = "CmdButton"
    button.Size = UDim2.new(0, Config.MobileButtonSize, 0, Config.MobileButtonSize)
    button.Position = UDim2.new(1, -Config.MobileButtonSize - 20, 1, -Config.MobileButtonSize - 100)
    button.BackgroundColor3 = Config.Theme.Primary
    button.Text = "CMD"
    button.TextColor3 = Config.Theme.Text
    button.Font = Enum.Font.GothamBold
    button.TextSize = 18
    button.Parent = mobileGui
    CreateCorner(Config.MobileButtonSize / 4).Parent = button
    CreateStroke(Config.Theme.Accent, 3).Parent = button
    
    -- Draggable functionality
    local dragging = false
    local dragStart = nil
    local startPos = nil
    
    button.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = button.Position
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.Touch then
            local delta = input.Position - dragStart
            button.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, 
                                       startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            if dragging then
                dragging = false
                -- Check if it was a tap vs drag
                local delta = input.Position - dragStart
                if delta.Magnitude < 15 then
                    HoneycombCMD:ShowCommandBar()
                end
            end
        end
    end)
end

-- Create floating command bar (mobile optimized)
local function CreateCommandBar()
    if cmdBarGui then
        cmdBarGui:Destroy()
    end
    
    cmdBarGui = Instance.new("ScreenGui")
    cmdBarGui.Name = "HoneycombCMDBar"
    cmdBarGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    cmdBarGui.DisplayOrder = 100
    cmdBarGui.ResetOnSpawn = false
    cmdBarGui.IgnoreGuiInset = true
    
    -- Mobile-responsive sizing
    local barWidth = 700
    local barHeight = 50
    
    -- Main container
    local container = Instance.new("Frame")
    container.Name = "Container"
    container.Size = UDim2.new(0, barWidth, 0, barHeight)
    container.Position = UDim2.new(0.5, -barWidth/2, 1, -80)
    container.BackgroundColor3 = Config.Theme.Primary
    container.Parent = cmdBarGui
    container.Visible = false
    CreateCorner(12).Parent = container
    CreateStroke(Config.Theme.Accent, 3).Parent = container
    
    -- Input box
    local inputBox = Instance.new("TextBox")
    inputBox.Name = "InputBox"
    inputBox.Size = UDim2.new(1, -20, 1, -10)
    inputBox.Position = UDim2.new(0, 10, 0, 5)
    inputBox.BackgroundTransparency = 1
    inputBox.Text = ""
    inputBox.PlaceholderText = "Enter command... (Tap for suggestions)"
    inputBox.PlaceholderColor3 = Config.Theme.TextDim
    inputBox.TextColor3 = Config.Theme.Text
    inputBox.Font = Enum.Font.GothamMedium
    inputBox.TextSize = 18
    inputBox.TextXAlignment = Enum.TextXAlignment.Left
    inputBox.ClearTextOnFocus = false
    inputBox.Parent = container
    
    -- Suggestions container
    local suggestionsFrame = Instance.new("Frame")
    suggestionsFrame.Name = "Suggestions"
    suggestionsFrame.Size = UDim2.new(1, 0, 0, 0)
    suggestionsFrame.Position = UDim2.new(0, 0, 0, -5)
    suggestionsFrame.BackgroundColor3 = Config.Theme.Secondary
    suggestionsFrame.Visible = false
    suggestionsFrame.Parent = container
    CreateCorner(12).Parent = suggestionsFrame
    CreateStroke(Config.Theme.Accent, 2).Parent = suggestionsFrame
    
    local suggestionsLayout = CreateLayout(Enum.FillDirection.Vertical, 4)
    suggestionsLayout.Parent = suggestionsFrame
    CreatePadding(8).Parent = suggestionsFrame
    
    -- Command bar functions
    local function ShowSuggestions(input)
        -- Clear existing suggestions
        for _, child in pairs(suggestionsFrame:GetChildren()) do
            if child:IsA("TextButton") then
                child:Destroy()
            end
        end
        
        suggestions = GetCommandSuggestions(input)
        currentSuggestionIndex = 0
        
        if #suggestions == 0 then
            suggestionsFrame.Visible = false
            return
        end
        
        -- Create suggestion items
        local itemHeight = 40
        for i, suggestion in ipairs(suggestions) do
            local item = Instance.new("TextButton")
            item.Size = UDim2.new(1, 0, 0, itemHeight)
            item.BackgroundColor3 = i == 1 and Config.Theme.AccentDark or Color3.fromRGB(0, 0, 0, 0)
            item.BackgroundTransparency = i == 1 and 0.8 or 1
            item.Parent = suggestionsFrame
            item.Text = ""
            CreateCorner(8).Parent = item
            
            -- Touch to select
            item.MouseButton1Click:Connect(function()
                inputBox.Text = PREFIX .. suggestion.name .. " "
                inputBox.CursorPosition = #inputBox.Text + 1
                suggestionsFrame.Visible = false
                inputBox:CaptureFocus()
            end)
            
            local nameLabel = Instance.new("TextLabel")
            nameLabel.Size = UDim2.new(0.35, 0, 1, 0)
            nameLabel.Position = UDim2.new(0, 12, 0, 0)
            nameLabel.BackgroundTransparency = 1
            nameLabel.Text = PREFIX .. suggestion.name
            nameLabel.TextColor3 = Config.Theme.TextAccent
            nameLabel.Font = Enum.Font.GothamBold
            nameLabel.TextSize = 16
            nameLabel.TextXAlignment = Enum.TextXAlignment.Left
            nameLabel.Parent = item
            
            local descLabel = Instance.new("TextLabel")
            descLabel.Size = UDim2.new(0.65, -20, 1, 0)
            descLabel.Position = UDim2.new(0.35, 0, 0, 0)
            descLabel.BackgroundTransparency = 1
            descLabel.Text = suggestion.description
            descLabel.TextColor3 = Config.Theme.TextDim
            descLabel.Font = Enum.Font.Gotham
            descLabel.TextSize = 14
            descLabel.TextXAlignment = Enum.TextXAlignment.Left
            descLabel.TextWrapped = true
            descLabel.Parent = item
        end
        
        -- Resize suggestions frame with animation
        local targetHeight = math.min(#suggestions * (itemHeight + 6) + 24, 300)
        suggestionsFrame.Size = UDim2.new(1, 0, 0, 0)
        suggestionsFrame.Position = UDim2.new(0, 0, 0, -10)
        suggestionsFrame.Visible = true
        
        local expandAnim = TweenService:Create(suggestionsFrame,
            TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            {
                Size = UDim2.new(1, 0, 0, targetHeight),
                Position = UDim2.new(0, 0, 0, -targetHeight - 10)
            }
        )
        expandAnim:Play()
    end
    
    local function HideSuggestions()
        if suggestionsFrame.Visible then
            local collapseAnim = TweenService:Create(suggestionsFrame,
                TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
                {Size = UDim2.new(1, 0, 0, 0), Position = UDim2.new(0, 0, 0, -10)}
            )
            collapseAnim:Play()
            collapseAnim.Completed:Connect(function()
                suggestionsFrame.Visible = false
            end)
        end
        suggestions = {}
        currentSuggestionIndex = 0
    end
    
    -- Input handling
    inputBox.Changed:Connect(function(property)
        if property == "Text" then
            local text = inputBox.Text
            if text:sub(1, 1) == PREFIX then
                text = text:sub(2)
            end
            
            if text == "" then
                HideSuggestions()
            else
                ShowSuggestions(text)
            end
        end
    end)
    
    inputBox.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            local command = inputBox.Text
            if command:sub(1, 1) ~= PREFIX then
                command = PREFIX .. command
            end
            
            ExecuteCommand(command:sub(2))
            inputBox.Text = ""
            HideSuggestions()
            HoneycombCMD:HideCommandBar()
        end
    end)
    
    return container
end

-- Chat parser
local function EnableChatParser()
    if chatConnection then
        chatConnection:Disconnect()
    end
    
    -- Try new TextChatService first
    if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
        local textChannel = TextChatService:WaitForChild("TextChannels"):WaitForChild("RBXGeneral")
        
        chatConnection = textChannel.MessageReceived:Connect(function(message)
            if message.TextSource and message.TextSource.UserId == LocalPlayer.UserId then
                local text = message.Text
                if text:sub(1, 1) == PREFIX then
                    ExecuteCommand(text:sub(2))
                end
            end
        end)
    else
        -- Legacy chat system
        local success, chatEvents = pcall(function()
            return ReplicatedStorage:WaitForChild("DefaultChatSystemChatEvents", 5)
        end)
        
        if success and chatEvents then
            local messageDoneFiltering = chatEvents:WaitForChild("OnMessageDoneFiltering")
            
            chatConnection = messageDoneFiltering.OnClientEvent:Connect(function(messageData)
                if messageData.FromSpeaker == LocalPlayer.Name then
                    local text = messageData.Message
                    if text:sub(1, 1) == PREFIX then
                        ExecuteCommand(text:sub(2))
                    end
                end
            end)
        end
    end
end

-- API Functions
function HoneycombCMD:Initialize()
    self:Print("Initializing HoneycombCMD Mobile RC7 v2.1...")
    
    -- Create command bar
    CreateCommandBar()
    
    -- Create mobile buttons
    CreateMobileButton()
    
    -- Create main GUI
    CreateMainGui()
    
    -- Enable chat parser
    EnableChatParser()
    
    -- Register built-in commands
    self:RegisterCommand("help", {
        {name = "command", type = "string", required = false}
    }, function(args)
        if args[1] then
            local cmd = commands[args[1]:lower()]
            if cmd then
                local helpText = PREFIX .. args[1]
                if cmd.usage then
                    helpText = cmd.usage
                end
                if cmd.description then
                    helpText = helpText .. " - " .. cmd.description
                end
                ShowNotification(helpText, "info", 6)
            else
                ShowNotification("Command not found: " .. args[1], "error")
            end
        else
            local cmdList = {}
            for name, _ in pairs(commands) do
                table.insert(cmdList, name)
            end
            table.sort(cmdList)
            ShowNotification("Available commands (" .. #cmdList .. "): " .. table.concat(cmdList, ", "), "info", 8)
        end
    end, "Show help for commands", PREFIX .. "help [command]")
    
    self:RegisterCommand("cmdbar", {}, function()
        self:ShowCommandBar()
    end, "Open the command bar", PREFIX .. "cmdbar")
    
    self:RegisterCommand("gui", {}, function()
        self:ToggleMainGui()
    end, "Toggle main GUI window", PREFIX .. "gui")
    
    self:RegisterCommand("history", {}, function()
        if #commandHistory == 0 then
            ShowNotification("No command history", "info")
        else
            local history = "Recent commands: " .. table.concat(commandHistory, ", ")
            ShowNotification(history:sub(1, 250) .. (history:len() > 250 and "..." or ""), "info", 8)
        end
    end, "Show command history", PREFIX .. "history")
    
    self:RegisterCommand("clear", {}, function()
        commandHistory = {}
        ShowNotification("Command history cleared", "success")
    end, "Clear command history", PREFIX .. "clear")
    
    self:RegisterCommand("players", {}, function()
        UpdatePlayersList()
        local playerNames = {}
        for _, playerData in pairs(playersList) do
            local displayText = playerData.name
            if playerData.name ~= playerData.displayName then
                displayText = displayText .. " (" .. playerData.displayName .. ")"
            end
            table.insert(playerNames, displayText)
        end
        ShowNotification("Online players (" .. #playerNames .. "): " .. table.concat(playerNames, ", "), "info", 10)
    end, "List all online players", PREFIX .. "players")
    
    self:RegisterCommand("theme", {
        {name = "color", type = "string", required = true}
    }, function(args)
        local color = args[1]:lower()
        if color == "red" then
            Config.Theme.Accent = Color3.fromRGB(255, 60, 60)
            Config.Theme.AccentDark = Color3.fromRGB(200, 45, 45)
            Config.Theme.AccentGlow = Color3.fromRGB(255, 100, 100)
            Config.Theme.TextAccent = Color3.fromRGB(255, 80, 80)
        elseif color == "blue" then
            Config.Theme.Accent = Color3.fromRGB(60, 150, 255)
            Config.Theme.AccentDark = Color3.fromRGB(45, 120, 200)
            Config.Theme.AccentGlow = Color3.fromRGB(100, 170, 255)
            Config.Theme.TextAccent = Color3.fromRGB(80, 160, 255)
        elseif color == "green" then
            Config.Theme.Accent = Color3.fromRGB(60, 255, 60)
            Config.Theme.AccentDark = Color3.fromRGB(45, 200, 45)
            Config.Theme.AccentGlow = Color3.fromRGB(100, 255, 100)
            Config.Theme.TextAccent = Color3.fromRGB(80, 255, 80)
        elseif color == "purple" then
            Config.Theme.Accent = Color3.fromRGB(150, 60, 255)
            Config.Theme.AccentDark = Color3.fromRGB(120, 45, 200)
            Config.Theme.AccentGlow = Color3.fromRGB(170, 100, 255)
            Config.Theme.TextAccent = Color3.fromRGB(160, 80, 255)
        else
            ShowNotification("Available themes: red, blue, green, purple", "error")
            return
        end
        ShowNotification("Theme changed to " .. color, "success")
    end, "Change UI theme color", PREFIX .. "theme <red/blue/green/purple>")
    
    self:Print("Initialized! Tap CMD for command bar, GUI for main window")
    ShowNotification("HoneycombCMD RC7 v2.1 loaded! • " .. PREFIX .. " prefix • Tap CMD/GUI buttons", "success", 6)
end

function HoneycombCMD:RegisterCommand(name, args, callback, description, usage)
    name = name:lower()
    commands[name] = {
        callback = callback,
        args = args,
        description = description,
        usage = usage or (PREFIX .. name)
    }
    self:Print("Registered command: " .. name)
end

function HoneycombCMD:ShowCommandBar()
    if not cmdBarGui then return end
    
    local container = cmdBarGui:FindFirstChild("Container")
    if not container then return end
    
    isCommandBarOpen = true
    container.Visible = true
    
    local inputBox = container:FindFirstChild("InputBox")
    if inputBox then
        inputBox:CaptureFocus()
    end
    
    -- Enhanced animation
    container.Position = UDim2.new(0.5, -375, 1, 80)
    container.Size = UDim2.new(0, 0, 0, 60)
    
    local slideAnim = TweenService:Create(container,
        TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {Position = UDim2.new(0.5, -375, 1, -90)}
    )
    local expandAnim = TweenService:Create(container,
        TweenInfo.new(0.5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
        {Size = UDim2.new(0, 750, 0, 60)}
    )
    
    slideAnim:Play()
    task.wait(0.1)
    expandAnim:Play()
end

function HoneycombCMD:HideCommandBar()
    if not cmdBarGui then return end
    
    local container = cmdBarGui:FindFirstChild("Container")
    if not container then return end
    
    isCommandBarOpen = false
    
    local inputBox = container:FindFirstChild("InputBox")
    if inputBox then
        inputBox:ReleaseFocus()
        inputBox.Text = ""
    end
    
    -- Hide suggestions
    local suggestions = container:FindFirstChild("Suggestions")
    if suggestions then
        suggestions.Visible = false
    end
    
    -- Enhanced animation
    local shrinkAnim = TweenService:Create(container,
        TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        {Size = UDim2.new(0, 0, 0, 60)}
    )
    local slideAnim = TweenService:Create(container,
        TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.In),
        {Position = UDim2.new(0.5, -375, 1, 80)}
    )
    
    shrinkAnim:Play()
    shrinkAnim.Completed:Connect(function()
        slideAnim:Play()
        slideAnim.Completed:Connect(function()
            container.Visible = false
        end)
    end)
end

function HoneycombCMD:ToggleMainGui()
    if not mainGui then return end
    
    local window = mainGui:FindFirstChild("MainWindow")
    if not window then return end
    
    if isMainGuiOpen then
        self:HideMainGui()
    else
        self:ShowMainGui()
    end
end

function HoneycombCMD:ShowMainGui()
    if not mainGui then return end
    
    local window = mainGui:FindFirstChild("MainWindow")
    if not window then return end
    
    isMainGuiOpen = true
    window.Visible = true
    
    -- Enhanced show animation
    window.Size = UDim2.new(0, 0, 0, 0)
    window.Position = UDim2.new(0.5, 0, 0.5, 0)
    
    local expandAnim = TweenService:Create(window,
        TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {
            Size = UDim2.new(0, 600, 0, 450),
            Position = UDim2.new(0.5, -300, 0.5, -225)
        }
    )
    expandAnim:Play()
end

function HoneycombCMD:HideMainGui()
    if not mainGui then return end
    
    local window = mainGui:FindFirstChild("MainWindow")
    if not window then return end
    
    isMainGuiOpen = false
    
    -- Enhanced hide animation
    local shrinkAnim = TweenService:Create(window,
        TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In),
        {
            Size = UDim2.new(0, 0, 0, 0),
            Position = UDim2.new(0.5, 0, 0.5, 0)
        }
    )
    shrinkAnim:Play()
    shrinkAnim.Completed:Connect(function()
        window.Visible = false
    end)
end

function HoneycombCMD:ExecuteCommand(commandLine)
    return ExecuteCommand(commandLine)
end

function HoneycombCMD:GetCommands()
    return commands
end

function HoneycombCMD:SetPrefix(prefix)
    PREFIX = prefix
end

function HoneycombCMD:SetTheme(theme)
    for key, value in pairs(theme) do
        if Config.Theme[key] then
            Config.Theme[key] = value
        end
    end
end

function HoneycombCMD:Print(text)
    print("[HoneycombCMD]: " .. tostring(text))
end

return HoneycombCMD(0.3, 0, 1, 0)
            nameLabel.Position = UDim2.new(0, 8, 0, 0)
            nameLabel.BackgroundTransparency = 1
            nameLabel.Text = PREFIX .. suggestion.name
            nameLabel.TextColor3 = Config.Theme.Accent
            nameLabel.Font = Enum.Font.GothamBold
            nameLabel.TextSize = 16
            nameLabel.TextXAlignment = Enum.TextXAlignment.Left
            nameLabel.Parent = item
            
            local descLabel = Instance.new("TextLabel")
            descLabel.Size = UDim2.new(0.7, -16, 1, 0)
            descLabel.Position = UDim2.new(0.3, 0, 0, 0)
            descLabel.BackgroundTransparency = 1
            descLabel.Text = suggestion.description
            descLabel.TextColor3 = Config.Theme.TextDim
            descLabel.Font = Enum.Font.Gotham
            descLabel.TextSize = 14
            descLabel.TextXAlignment = Enum.TextXAlignment.Left
            descLabel.Parent = item
        end
        
        -- Resize suggestions frame
        suggestionsFrame.Size = UDim2.new(1, 0, 0, math.min(#suggestions * (itemHeight + 4) + 16, 250))
        suggestionsFrame.Position = UDim2.new(0, 0, 0, -suggestionsFrame.Size.Y.Offset - 5)
        suggestionsFrame.Visible = true
    end
    
    local function HideSuggestions()
        suggestionsFrame.Visible = false
        suggestions = {}
        currentSuggestionIndex = 0
    end
    
    -- Input handling
    inputBox.Changed:Connect(function(property)
        if property == "Text" then
            local text = inputBox.Text
            if text:sub(1, 1) == PREFIX then
                text = text:sub(2)
            end
            
            if text == "" then
                HideSuggestions()
            else
                ShowSuggestions(text)
            end
        end
    end)
    
    inputBox.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            local command = inputBox.Text
            if command:sub(1, 1) ~= PREFIX then
                command = PREFIX .. command
            end
            
            ExecuteCommand(command:sub(2))
            inputBox.Text = ""
            HideSuggestions()
            HoneycombCMD:HideCommandBar()
        end
    end)
    
    return container
end

-- Chat parser
local function EnableChatParser()
    if chatConnection then
        chatConnection:Disconnect()
    end
    
    -- Try new TextChatService first
    if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
        local textChannel = TextChatService:WaitForChild("TextChannels"):WaitForChild("RBXGeneral")
        
        chatConnection = textChannel.MessageReceived:Connect(function(message)
            if message.TextSource and message.TextSource.UserId == LocalPlayer.UserId then
                local text = message.Text
                if text:sub(1, 1) == PREFIX then
                    ExecuteCommand(text:sub(2))
                end
            end
        end)
    else
        -- Legacy chat system
        local success, chatEvents = pcall(function()
            return ReplicatedStorage:WaitForChild("DefaultChatSystemChatEvents", 5)
        end)
        
        if success and chatEvents then
            local messageDoneFiltering = chatEvents:WaitForChild("OnMessageDoneFiltering")
            
            chatConnection = messageDoneFiltering.OnClientEvent:Connect(function(messageData)
                if messageData.FromSpeaker == LocalPlayer.Name then
                    local text = messageData.Message
                    if text:sub(1, 1) == PREFIX then
                        ExecuteCommand(text:sub(2))
                    end
                end
            end)
        end
    end
end

-- API Functions
function HoneycombCMD:Initialize()
    self:Print("Initializing HoneycombCMD Mobile v2.0...")
    
    -- Create command bar
    CreateCommandBar()
    
    -- Create mobile button
    CreateMobileButton()
    
    -- Enable chat parser
    EnableChatParser()
    
    -- Register built-in commands
    self:RegisterCommand("help", {
        {name = "command", type = "string", required = false}
    }, function(args)
        if args[1] then
            local cmd = commands[args[1]:lower()]
            if cmd then
                local helpText = PREFIX .. args[1]
                if cmd.usage then
                    helpText = cmd.usage
                end
                if cmd.description then
                    helpText = helpText .. " - " .. cmd.description
                end
                ShowNotification(helpText, "info", 6)
            else
                ShowNotification("Command not found: " .. args[1], "error")
            end
        else
            local cmdList = {}
            for name, _ in pairs(commands) do
                table.insert(cmdList, name)
            end
            table.sort(cmdList)
            ShowNotification("Available commands: " .. table.concat(cmdList, ", "), "info", 8)
        end
    end, "Show help for commands", PREFIX .. "help [command]")
    
    self:RegisterCommand("cmdbar", {}, function()
        self:ShowCommandBar()
    end, "Open the command bar", PREFIX .. "cmdbar")
    
    self:RegisterCommand("history", {}, function()
        if #commandHistory == 0 then
            ShowNotification("No command history", "info")
        else
            local history = "Recent commands: " .. table.concat(commandHistory, ", ")
            ShowNotification(history:sub(1, 200) .. (history:len() > 200 and "..." or ""), "info", 6)
        end
    end, "Show command history", PREFIX .. "history")
    
    self:RegisterCommand("clear", {}, function()
        commandHistory = {}
        ShowNotification("Command history cleared", "success")
    end, "Clear command history", PREFIX .. "clear")
    
    self:RegisterCommand("players", {}, function()
        UpdatePlayersList()
        local playerNames = {}
        for _, playerData in pairs(playersList) do
            local displayText = playerData.name
            if playerData.name ~= playerData.displayName then
                displayText = displayText .. " (" .. playerData.displayName .. ")"
            end
            table.insert(playerNames, displayText)
        end
        ShowNotification("Online players: " .. table.concat(playerNames, ", "), "info", 8)
    end, "List all online players", PREFIX .. "players")
    
    self:Print("Initialized! Tap the CMD button or use chat commands with '" .. PREFIX .. "'")
    ShowNotification("HoneycombCMD Mobile v2.0 loaded! Prefix: " .. PREFIX .. " | Tap CMD button", "success", 5)
end

function HoneycombCMD:RegisterCommand(name, args, callback, description, usage)
    name = name:lower()
    commands[name] = {
        callback = callback,
        args = args,
        description = description,
        usage = usage or (PREFIX .. name)
    }
    self:Print("Registered command: " .. name)
end

function HoneycombCMD:ShowCommandBar()
    if not cmdBarGui then return end
    
    local container = cmdBarGui:FindFirstChild("Container")
    if not container then return end
    
    isCommandBarOpen = true
    container.Visible = true
    
    local inputBox = container:FindFirstChild("InputBox")
    if inputBox then
        inputBox:CaptureFocus()
    end
    
    -- Animation
    container.Position = UDim2.new(0.5, -container.Size.X.Offset/2, 1, 50)
    local tween = TweenService:Create(container,
        TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {Position = UDim2.new(0.5, -container.Size.X.Offset/2, 1, -80)}
    )
    tween:Play()
end

function HoneycombCMD:HideCommandBar()
    if not cmdBarGui then return end
    
    local container = cmdBarGui:FindFirstChild("Container")
    if not container then return end
    
    isCommandBarOpen = false
    
    local inputBox = container:FindFirstChild("InputBox")
    if inputBox then
        inputBox:ReleaseFocus()
        inputBox.Text = ""
    end
    
    -- Hide suggestions
    local suggestions = container:FindFirstChild("Suggestions")
    if suggestions then
        suggestions.Visible = false
    end
    
    -- Animation
    local tween = TweenService:Create(container,
        TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        {Position = UDim2.new(0.5, -container.Size.X.Offset/2, 1, 50)}
    )
    tween:Play()
    tween.Completed:Connect(function()
        container.Visible = false
    end)
end

function HoneycombCMD:ExecuteCommand(commandLine)
    return ExecuteCommand(commandLine)
end

function HoneycombCMD:GetCommands()
    return commands
end

function HoneycombCMD:SetPrefix(prefix)
    PREFIX = prefix
end

function HoneycombCMD:SetTheme(theme)
    for key, value in pairs(theme) do
        if Config.Theme[key] then
            Config.Theme[key] = value
        end
    end
end

function HoneycombCMD:Print(text)
    print("[HoneycombCMD]: " .. tostring(text))
end

return HoneycombCMD