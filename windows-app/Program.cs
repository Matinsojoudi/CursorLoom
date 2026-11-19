namespace InputBridge.Windows;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();
        Application.Run(new MainWindow());
    }
}

internal sealed class MainWindow : Form
{
    public MainWindow()
    {
        Text = "InputBridge — development preview";
        Width = 560;
        Height = 270;
        StartPosition = FormStartPosition.CenterScreen;
        var panel = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.TopDown,
            Padding = new Padding(24),
            WrapContents = false,
            AutoScroll = true
        };
        panel.Controls.Add(new Label { Text = "InputBridge", AutoSize = true, Font = new Font(Font.FontFamily, 20, FontStyle.Bold) });
        panel.Controls.Add(new Label { Text = "Development preview — remote control is disabled.", AutoSize = true, Margin = new Padding(3, 16, 3, 3) });
        panel.Controls.Add(new Label { Text = "Secure connection and device pairing are not yet available.", AutoSize = true });
        Controls.Add(panel);
    }
}
