
using System;
using System.Collections;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Reflection;


public enum NetworkCategory{Public,Private,Authenticated}

[Flags]
public enum NetworkConnectivityLevels {Connected = 1,Disconnected = 2,All = 3}

[ComImport]
[TypeLibType((short)0x1040)]
[Guid("DCB00002-570F-4A9B-8D69-199FDBA5723B")]
public interface INetwork{}

[ComImport]
[Guid("DCB00000-570F-4A9B-8D69-199FDBA5723B")]
[TypeLibType((short)0x1040)]
public interface INetworkListManager
{
    [return: MarshalAs(UnmanagedType.Interface)]
    [MethodImpl(MethodImplOptions.InternalCall, MethodCodeType = MethodCodeType.Runtime)]
    IEnumerable GetNetworks([In] NetworkConnectivityLevels Flags);
}

public class WinImageBuilderAutomation
{
    public static void Run()
    {
        SetNetworksLocationToPrivate();
    }
    public static void SetNetworksLocationToPrivate()
    {
        INetworkListManager nlm = (INetworkListManager)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("DCB00C01-570F-4A9B-8D69-199FDBA5723B")));
        IEnumerable networks = nlm.GetNetworks(NetworkConnectivityLevels.All);
        foreach (INetwork network in networks)
        {
            Type comType = typeof(INetwork);
            object[] parameters = { NetworkCategory.Private };
            comType.InvokeMember("SetCategory", BindingFlags.InvokeMethod, null, network, parameters);
        }

    }
}
