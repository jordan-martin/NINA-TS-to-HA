This is a powershell script to send active N.I.N.A. Target Scheduler data to Home Assistant. I don't place any claim to the code, it's reliability, secuirty, etc... This was vibe coded using Gemini and functions on a private network with no public access. 

# Instructions To Get It Working

### Step 1: Prepare Home Assistant

Create a Long-Lived Access Token: This is the password your script will use.
- In Home Assistant, click on your user profile icon in the bottom-left corner.
- Scroll down to the "Long-Lived Access Tokens" section and click "Create Token".
- Give it a name (like nina_scheduler_script) and click "OK".
- Crucially, copy the token that appears and save it somewhere safe like a password manager. You will not be able to see it again.

### Step 2: Prepare Your Imaging PC

Edit the three variables at the top of the nina_to_ha powershell script:
- DB_PATH: Replace <YourUsername> with the path to your TS SQLite database
- HA_URL: Change YOUR_HA_ADDRESS to the IP address or hostname of your Home Assistant instance (e.g., http://192.168.1.50:8123).
- HA_TOKEN: Paste the Long-Lived Access Token you created.

PowerShell doesn't have a built-in SQLite reader, so you need to install a trusted module from the PowerShell Gallery to handle it. This is a simple, one-time setup.
- Click the Start Menu, type PowerShell, right-click on Windows PowerShell, and select Run as administrator.
- In the blue PowerShell window that appears, copy and paste the following command and press Enter:
  ```
  PowerShell Install-Module -Name PSSQLite -Force
  ```
- You may be asked about installing from an "untrusted repository." The PowerShell Gallery is the standard, trusted source for modules, so you can accept.

### Step 3: Test your setup by running the code manually

You should be able to run your code in a powershell window. You should receive either a message telling you that data was successfully sent, or an error message. You can verify if the data is in Home Assistant using the following procedure:

- In Home Assistant, go to Developer Tools (the little hammer icon on the left sidebar).
- Stay on the States tab.
- In the "Filter entities" box, type sensor.nina_scheduler_status to find our sensor.
- Click on it, and look at the Attributes on the right side of the page.

### Step 4: Automate The Running Of the Script
- Press the Windows Key on your keyboard.
- Type Task Scheduler and click on the app to open it.
- In the "Actions" pane on the right side of the window, click on Create Task... (Do not use "Create Basic Task" as it offers fewer options). A new window with multiple tabs will open.
- Configure the "General" Tab
  - Name: Give the task a descriptive name, like NINA to Home Assistant Sync.
  - Security options:
    - Select the option "Run whether user is logged on or not". This is crucial for an imaging PC that might be running unattended overnight.
    - Check the box for "Run with highest privileges". This helps prevent any potential permissions issues.
  - Configure for: Make sure "Windows 10 / Windows 11" is selected at the bottom.
- Configure the "Triggers" Tab
  - Click the New... button.
    - Begin the task: On a schedule
    - Settings: Daily
    - Check the box for "Repeat task every:"
    - In the dropdown next to it, select how often you would like the script to run.
    - For the duration, select Indefinitely.
    - At the bottom, ensure the "Enabled" checkbox is checked.
    - Click OK.
- Configure the "Actions" Tab
  - Click the New... button.
    - Action: Leave this as "Start a program".
    - Program/script: Type powershell.exe
    - Add arguments (optional): Copy and paste the entire following line into this box. Be sure to replace <path_to_script> with the path to your script.
      
        ```
        -ExecutionPolicy Bypass -File "<path_to_script>"
        ```
    - Click OK.
- Configure the "Conditions" Tab
  - I recommend unchecking the box for "Start the task only if the computer is on AC power". This ensures the script still runs if your imaging rig is temporarily on a battery backup.
- Finalize and Save
  - Click the main OK button to save your new task.
  - Because you selected "Run whether user is logged on or not," Windows will now prompt you to enter the password for your user account. This is required to allow the task to run in the background.
  - Enter your password and click OK.

Your task is now created and will automatically trigger every 10 minutes.

### Step 5: Display your data in Home Assistant

I'm still not 100% happy with how I have the data displayed but I'm happy to share what I currently have set up as a starting point. I use a grid card, but the same markdown should work in a true markdown card:

```
square: true
type: grid
cards:
  - type: markdown
    entity_id: sensor.nina_scheduler_status
    content: >
      {% for project in state_attr('sensor.nina_scheduler_status', 'projects')
      %}

      ## {{ project.project_name }}
        {% for target in project.targets %}
      **{{ target.target_name }}**
        ```text
        {% for f in target.filter_progress %}
        {{ f.name }}: {{ f.percent }}%
        {% endfor %}
        ```
        {% endfor %}
      {% endfor %}
columns: 1
grid_options:
  columns: 48
  rows: auto
```
