using Uno;
using Uno.Collections;
using Uno.Text;
using Uno.UX;

using Fuse.Internal;

namespace Fuse
{
	public partial class Visual
	{
		// Performance critical code paths should not need to create this array.
		// This is here to optimize the corner cases where we need indexed lookup.
		// The SafeIterator also takes advantage of this if available at the time
		// it needs a copy
		Node[] Children_cachedArray;
		Node[] Children_GetCachedArray()
		{
			if (Children_cachedArray != null) return Children_cachedArray;

			var nodes = new Node[_childCount];
			var c = _firstChild;
			int i = 0;
			while (c != null)
			{
				nodes[i] = c;
				c = c._nextSibling;
			}
			Children_cachedArray = nodes;
			return nodes;
		}

		Node Children_ItemAt(int index)
		{
			var arr = Children_GetCachedArray();
			return arr[index];
		}

		void Children_Invalidate()
		{
			if (_safeIterator != null) _safeIterator.SecureCopy();
			Children_cachedArray = null;
		}

		IEnumerator<Node> Children_GetEnumerator()
		{
			return new SafeIterator(this);
		}

		SafeIterator _safeIterator; // Linked list

		class SafeIterator: IEnumerator<Node>
		{
			Node[] _array;
			int _pos = -1;
			Node _current;
			SafeIterator _nextIterator;
			Visual _v;

			internal SafeIterator(Visual v)
			{
				_v = v;
			}

			public Node Current
			{
				get
				{
					if (_array != null) return _array[_pos];
					else return _current;
				}
			}

			public bool MoveNext()
			{
				if (_pos == -1)
				{
					AddToIteratorList();
					_array = _v.Children_cachedArray; // If we have a cached array, go ahead and use that
				}

				var res = MoveNextInternal();
				if (!res) RemoveFromIteratorList();
				return res;
			}

			bool MoveNextInternal()
			{
				_pos++;

				if (_array != null)
					return _pos < _array.Length;
				
				if (_current == null) _current = _v._firstChild;
				else _current = _current._nextSibling;

				return _current != null;
			}

			public void Dispose()
			{
				Reset();
				_v = null;
			}

			public void Reset()
			{
				_pos = -1;
				_current = null;
				_array = null;
				RemoveFromIteratorList();
			}

			void AddToIteratorList()
			{
				_nextIterator = _v._safeIterator;
				_v._safeIterator = this;
			}

			void RemoveFromIteratorList()
			{
				if (_v._safeIterator == this)
				{
					_v._safeIterator = _nextIterator;
					_v._safeIterator = null;
				}
				else
				{
					for (var si = _v._safeIterator; si != null; si = si._nextIterator)
						if (si._nextIterator == this)
						{
							si._nextIterator = this._nextIterator;
							return;
						}
				}
			}

			internal void SecureCopy()
			{
				if (_pos != -1 && _array == null)
					CopyRemainingNodes();
			}

			void CopyRemainingNodes()
			{
				_array = new Node[_v._childCount-_pos];
				int i = 0;
				while (_current != null)
				{
					_array[i++] = _current;
					_current = _current._nextSibling;
				}
				// the copied array is just a subset, so reset index
				_pos = 0; 

				// tempting, but not correct. when _pos != -1, it uses _array[_pos]
				// _current = _array[0]; 
			}
		}
	}
}