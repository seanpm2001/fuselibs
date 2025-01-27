using Uno;
using Uno.Graphics;
using Uno.UX;
using Uno.Collections;
using Uno.Compiler.ExportTargetInterop;
using Uno.Graphics.Utils;
using Fuse.Resources.Exif;

namespace Fuse.Resources
{
	static class FileImageSourceCache
	{
		static Dictionary<FileSource,WeakReference<FileImageSourceImpl>> _cache =
			new Dictionary<FileSource,WeakReference<FileImageSourceImpl>>();
		static public FileImageSourceImpl GetFileSource(FileSource file, int2 targetSize)
		{
			WeakReference<FileImageSourceImpl> value = null;
			if(_cache.TryGetValue(file, out value))
			{
				FileImageSourceImpl his;
				if(value.TryGetTarget(out his))
					return his;
				_cache.Remove(file);
			}

			var nv = new FileImageSourceImpl(file, targetSize);
			_cache.Add(file, new WeakReference<FileImageSourceImpl>(nv));
			return nv;
		}
	}

	/** Specifies an image file as a data source to be displayed by an @Image element.

		The file pointed to by the `File` property will be added to the app as a bundle file automatically.

		## Example
		This example displays an image from the file `kitten.jpg`:
		```xml
			<Image>
				<FileImageSource File="kitten.jpg" />
			</Image>
		```
		## Referencing from JavaScript

		When building your project, Fuse needs to know which files to bundle with the app.
		Since UX is statically compiled, it will automatically bundle files whose path is hard-coded in one of the UX files in your project.

		However, if the path comes from JavaScript or some other dynamic data source, it cannot automatically be inferred by the compiler.
		Thus, we need to explicitly specify it as a [bundle file](articles:assets/bundle) in our `.unoproj`:
		```json
			"Includes": [
				"assets/kitten.jpg:Bundle"
			]
		```
		We can now use JavaScript to specify the path to the image:
		```xml
			<JavaScript>
				module.exports = {
					image: "assets/kitten.jpg"
				}
			</JavaScript>

			<Image>
				<FileImageSource File="{image}" />
			</Image>
		```
	*/
	public sealed class FileImageSource : ImageSource
	{
		/** The Target size of the image to resize.
		*/
		public int2 TargetSize { get; set; }

		/** Specifies a path to an image file.

		This file will automatically be added to the app as a bundle file.

		*/
		public FileSource File
		{
			get { return _proxy.Impl == null ? null : (_proxy.Impl as FileImageSourceImpl).File; }
			set
			{
				_proxy.Release();
				if( value == null )
					return;

				var bf = FileImageSourceCache.GetFileSource(value, TargetSize);
				_proxy.Attach(bf);
			}
		}

		internal new bool TestIsClean
		{
			get { return _proxy.Impl == null || (_proxy.Impl as FileImageSourceImpl).TestIsClean; }
		}

		ProxyImageSource _proxy;
		public FileImageSource(FileSource file)
		{
			_proxy = new ProxyImageSource(this);
			File = file;
		}

		public FileImageSource()
		{
			_proxy = new ProxyImageSource(this);
		}

		public MemoryPolicy DefaultPolicy
		{
			set
			{
				_proxy.DefaultSetPolicy(value);
			}
		}

		/** Specifies a hint for how the file resource should be kept in memory and when it can be unloaded.

		See @MemoryPolicy for more info.

		*/
		public MemoryPolicy Policy
		{
			get { return _proxy.Policy; }
			set
			{
				_proxy.Policy = value;
			}
		}
		protected override void OnPinChanged() {  _proxy.OnPinChanged(); }
		public override ImageOrientation Orientation { get { return _proxy.Orientation; } }
		public override float2 Size { get { return _proxy.Size; } }
		public override int2 PixelSize { get { return _proxy.PixelSize; } }
		public override ImageSourceState State { get { return _proxy.State; } }
		public override texture2D GetTexture() { return _proxy.GetTexture(); }
		public override byte[] GetBytes() { return _proxy.GetBytes(); }
		public override void Reload() { _proxy.Reload(); }
		public override void Load() { _proxy.Load(); }
		public override float SizeDensity { get { return Density; } }

		//shared public interface
		/** Specifies the source's pixel density.
		*/
		public float Density { get { return _proxy.Density; } set { _proxy.Density = value; } }
	}

	[extern(ANDROID) Require("Source.Include", "Uno/Graphics/GLHelper.h")]
	class FileImageSourceImpl : LoadingImageSource
	{
		FileSource _file;
		int2 _targetSize;

		[UXContent]
		public FileSource File
		{
			get { return _file; }
		}

		public FileImageSourceImpl(FileSource file, int2 targetSize)
		{
			if (file == null)
				throw new ArgumentNullException(nameof(file));

			_file = file;
			_targetSize = targetSize;
			_file.DataChanged += OnDataChanged;
		}

		~FileImageSourceImpl()
		{
			_file.DataChanged -= OnDataChanged;
		}

		void OnDataChanged(object s, object a)
		{
			Reload();
		}

		public void SyncLoad()
		{
			if (IsLoaded)
			{
				MarkUsed();
				return;
			}

			try
			{
				if defined(Android)
				{
					// HACK: make sure we have a current context!
					if (UpdateManager.CurrentStage != UpdateStage.Draw)
					@{
						try
						{
							GLHelper::SwapBackToBackgroundSurface();
						}
						catch (const uBase::Exception &e)
						{
							U_THROW(@{Uno.Exception(string):New(uString::Utf8(e.what()))});
						}
					@}
				}

				var data = _file.ReadAllBytes();
				data = ImageBackgroundLoad.ResizeImage(data, _targetSize);
				_orientation = ExifData.FromByteArray(data).Orientation;
				SetTexture(TextureLoader.Load2D(_file.Name, data));
				SetBytes(data);
				OnChanged();
			}
			catch (Exception e)
			{
				Cleanup(CleanupReason.Failed);
				OnError("Loading image from file failed. " + e.Message, e);
			}
		}

		ImageOrientation _orientation = ImageOrientation.Identity;
		public override ImageOrientation Orientation
		{
			get { return _orientation; }
		}

		protected override void AttemptLoad()
		{
			if (Policy.BundlePreload)
			{
				SyncLoad();
				return;
			}

			_loading = true;
			var imageBackgroundLoad = new ImageBackgroundLoad(_file, _targetSize, SuccessCallback, FailureCallback);
			imageBackgroundLoad.Dispatch();
			OnChanged();
		}

		void SuccessCallback(texture2D texture, byte[] bytes, ImageOrientation orientation)
		{
			_loading = false;
			_orientation = orientation;
			SetTexture(texture);
			SetBytes(bytes);
		}

		void FailureCallback(Exception e)
		{
			_loading = false;
			Cleanup(CleanupReason.Failed);
			OnError("Loading image from file failed. " + e.Message, e);
		}
	}
}
