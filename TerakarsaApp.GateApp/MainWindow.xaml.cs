using System.Windows;

namespace TerakarsaApp.GateApp;

public partial class MainWindow : Window
{
    public MainWindow(IServiceProvider services)
    {
        InitializeComponent();
        // IServiceProvider dari App.xaml.cs -- GateState & gate.db yang dipakai UI harus instance
        // yang SAMA dengan yang dipakai CardSyncService/TapQueueService.
        blazorWebView.Services = services;
    }
}
