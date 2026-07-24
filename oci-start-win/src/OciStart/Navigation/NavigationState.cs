using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace OciStart.Navigation;

public sealed class NavigationState : INotifyPropertyChanged
{
    public static NavigationState Shared { get; } = new();

    private NavId _selected = NavId.Dashboard;
    private string _searchText = "";
    private bool _sidebarCollapsed;

    public event PropertyChangedEventHandler? PropertyChanged;

    public NavId SelectedNav
    {
        get => _selected;
        set
        {
            if (_selected == value) return;
            _selected = value;
            OnPropertyChanged();
        }
    }

    public string SearchText
    {
        get => _searchText;
        set
        {
            if (_searchText == value) return;
            _searchText = value ?? "";
            OnPropertyChanged();
        }
    }

    public bool SidebarCollapsed
    {
        get => _sidebarCollapsed;
        set
        {
            if (_sidebarCollapsed == value) return;
            _sidebarCollapsed = value;
            OnPropertyChanged();
        }
    }

    private void OnPropertyChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
